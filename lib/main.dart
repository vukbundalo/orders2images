import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// HL7 folders
const String hl7InPath = r'C:\Temp\HL7\In';
const String hl7OutPath = r'C:\Temp\HL7\Out';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // initialize SQLite FFI
  sqfliteFfiInit();

  // ensure HL7 In/Out folders exist
  final inDir = Directory(hl7InPath);
  final outDir = Directory(hl7OutPath);
  if (!await inDir.exists()) await inDir.create(recursive: true);
  if (!await outDir.exists()) await outDir.create(recursive: true);

  // open database
  await DatabaseService.instance.db;
  runApp(const Order2ImageApp());
}

class Order2ImageApp extends StatelessWidget {
  const Order2ImageApp({super.key});

  // Dedalus brand colors
  static const Color dedalusPrimary = Color(0xFF005EB8);
  static const Color dedalusAccent = Color(0xFF78BE20);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Order2Image',
      theme: ThemeData(
        useMaterial3: false,
        primaryColor: dedalusPrimary,
        colorScheme: ColorScheme.fromSwatch().copyWith(
          secondary: dedalusAccent,
        ),
        cardTheme: const CardThemeData(
          elevation: 4,
          margin: EdgeInsets.all(8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // data lists
  List<Patient> patients = [];
  Patient? selectedPatient;
  List<OrderModel> orders = [];
  List<AuditEvent> events = [];
  List<ImageModel> capturedImages = [];

  // scroll controllers for auto-scroll
  final ScrollController _auditController = ScrollController();
  final ScrollController _imageController = ScrollController();

  // form state
  String? selectedProcedure;
  String? selectedPriority;
  final procedures = ['CT Abdomen', 'Chest X‑Ray', 'Brain MRI'];
  final priorities = ['Routine', 'STAT'];

  @override
  void initState() {
    super.initState();
    _loadAll();
    // watch for JSON files created by BridgeLink
    Directory(hl7OutPath).watch().listen((evt) async {
      if (evt.type == FileSystemEvent.create && evt.path.endsWith('.json')) {
        final fname = p.basename(evt.path);
        await DatabaseService.instance.logAudit('JSON_CREATED', fname);
        await _loadAudit();
      }
    });
  }

  @override
  void dispose() {
    _auditController.dispose();
    _imageController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await _loadPatients();
    await _loadOrders();
    await _loadAudit();
  }

  Future<void> _loadPatients() async {
    final rows = await DatabaseService.instance.getAllPatients();
    setState(() {
      patients = rows.map((m) => Patient.fromMap(m)).toList();
    });
  }

  Future<void> _loadOrders() async {
    orders = await DatabaseService.instance.getPendingOrders();
    setState(() {});
  }

  Future<void> _loadAudit() async {
    events = await DatabaseService.instance.getAuditLog();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_auditController.hasClients) {
        _auditController.jumpTo(_auditController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _loadCapturedImages(String patientId) async {
    capturedImages = await DatabaseService.instance.getImagesByPatient(
      patientId,
    );
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_imageController.hasClients) {
        _imageController.jumpTo(_imageController.position.maxScrollExtent);
      }
    });
  }

  String _buildHl7Message(
    Patient p,
    String orderId,
    String procedure,
    String priority,
  ) {
    // timestamp in YYYYMMDDHHMMSS
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[-:]'), '')
        .split('.')
        .first;
    return '''
MSH|^~\\&|APP|FAC|BRIDGELINK|BRIDGELINK|$ts||ORM^O01|$orderId|P|2.3
PID|1||${p.patientID}^^^FAC^MR||${p.lastName}^${p.firstName}||${p.dob}|${p.gender}
PV1|1|O
ORC|NW|$orderId^FAC|||$priority
OBR|1|$orderId^FAC||$procedure|||$ts
''';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Order2ImageApp.dedalusPrimary;
    final accent = Order2ImageApp.dedalusAccent;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order2Image'),
        backgroundColor: primary,
      ),
      body: Row(
        children: [
          // Doctor Dashboard
          Expanded(
            child: Card(
              child: Container(
                color: primary.withOpacity(0.05),
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Doctor Dashboard',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: primary,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // patient dropdown
                    DropdownButton<String>(
                      isExpanded: true,
                      hint: const Text('Select Patient'),
                      value: selectedPatient?.patientID,
                      items: patients.map((p) {
                        return DropdownMenuItem(
                          value: p.patientID,
                          child: Text('${p.firstName} ${p.lastName}'),
                        );
                      }).toList(),
                      onChanged: (id) async {
                        final p = patients.firstWhere((x) => x.patientID == id);
                        selectedPatient = p;
                        await _loadCapturedImages(p.patientID);
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 16),

                    // imaging request form
                    if (selectedPatient != null) ...[
                      Text(
                        'Request Imaging for '
                        '${selectedPatient!.firstName} ${selectedPatient!.lastName}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Procedure',
                        ),
                        items: procedures
                            .map(
                              (proc) => DropdownMenuItem(
                                value: proc,
                                child: Text(proc),
                              ),
                            )
                            .toList(),
                        value: selectedProcedure,
                        onChanged: (v) => setState(() => selectedProcedure = v),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Priority',
                        ),
                        items: priorities
                            .map(
                              (p) => DropdownMenuItem(value: p, child: Text(p)),
                            )
                            .toList(),
                        value: selectedPriority,
                        onChanged: (v) => setState(() => selectedPriority = v),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                        ),
                        onPressed:
                            (selectedProcedure != null &&
                                selectedPriority != null)
                            ? () async {
                                final orderId =
                                    'O${DateTime.now().millisecondsSinceEpoch}';
                                // insert into DB
                                await DatabaseService.instance.insertOrder(
                                  orderId: orderId,
                                  patientId: selectedPatient!.patientID,
                                  procedureCode: selectedProcedure!,
                                  orderDateTime: DateTime.now()
                                      .toIso8601String(),
                                );
                                await DatabaseService.instance.logAudit(
                                  'ORDER_CREATED',
                                  orderId,
                                );

                                // generate & write HL7
                                final msg = _buildHl7Message(
                                  selectedPatient!,
                                  orderId,
                                  selectedProcedure!,
                                  selectedPriority!,
                                );
                                final file = File(
                                  p.join(hl7InPath, '$orderId.hl7'),
                                );
                                // after:
                                await file.writeAsString(msg);
                                // log the entire message
                                await DatabaseService.instance.logAudit(
                                  'HL7_CREATED',
                                  msg,
                                );

                                // refresh views
                                await _loadOrders();
                                await _loadAudit();
                                await _loadCapturedImages(
                                  selectedPatient!.patientID,
                                );
                                selectedProcedure = null;
                                selectedPriority = null;
                                setState(() {});
                              }
                            : null,
                        child: const Text('Send Order'),
                      ),
                    ],

                    const Spacer(),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'Captured Images:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 150,
                      child: capturedImages.isEmpty
                          ? const Center(child: Text('No images captured yet.'))
                          : ListView.builder(
                              controller: _imageController,
                              itemCount: capturedImages.length,
                              itemBuilder: (_, i) {
                                final img = capturedImages[i];
                                final date = img.studyDate.substring(0, 10);
                                final time = img.studyDate.substring(11, 19);
                                return ListTile(
                                  dense: true,
                                  title: Text(img.modality),
                                  subtitle: Text('$date $time'),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Audit & Timeline
          Expanded(
            child: Card(
              child: Container(
                color: Colors.grey.shade100,
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Audit & Timeline',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: events.isEmpty
                          ? const Center(child: Text('No audit events yet.'))
                          : Expanded(
                              child: events.isEmpty
                                  ? const Center(
                                      child: Text('No audit events yet.'),
                                    )
                                  : ListView.builder(
                                      controller: _auditController,
                                      itemCount: events.length,
                                      itemBuilder: (context, i) {
                                        final e = events[i];
                                        if (e.eventType == 'HL7_CREATED') {
                                          return Card(
                                            margin: const EdgeInsets.symmetric(
                                              vertical: 4,
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(
                                                8.0,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'HL7 Message Created',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Theme.of(
                                                        context,
                                                      ).primaryColor,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  // show the full HL7 (multi‑line)
                                                  SelectableText(
                                                    e.refId,
                                                    style: const TextStyle(
                                                      fontFamily: 'monospace',
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        } else {
                                          // all other events stay as before
                                          return ListTile(
                                            dense: true,
                                            leading: Text(
                                              e.time.substring(11, 19),
                                            ),
                                            title: Text(
                                              '${e.eventType} → ${e.refId}',
                                            ),
                                          );
                                        }
                                      },
                                    ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Imaging Dashboard
          Expanded(
            child: Card(
              child: Container(
                color: Order2ImageApp.dedalusAccent.withOpacity(0.2),
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Imaging Dashboard',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: orders.isEmpty
                          ? const Center(child: Text('No pending orders'))
                          : ListView.builder(
                              itemCount: orders.length,
                              itemBuilder: (_, i) {
                                final o = orders[i];
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: ListTile(
                                    title: Text(o.procedureCode),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Patient: ${o.patientName}'),
                                        Text(
                                          'Ordered: ${o.orderDateTime.substring(0, 16)}',
                                        ),
                                      ],
                                    ),
                                    trailing: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: primary,
                                      ),
                                      onPressed: () async {
                                        final imageId =
                                            'IMG${DateTime.now().millisecondsSinceEpoch}';
                                        final studyDateTime = DateTime.now()
                                            .toIso8601String();
                                        final filePath =
                                            'C:/MiniPACS/DICOM/Out/$imageId.dcm';
                                        await DatabaseService.instance
                                            .insertImage(
                                              imageId: imageId,
                                              orderId: o.orderId,
                                              patientId: o.patientId,
                                              filePath: filePath,
                                              studyDate: studyDateTime,
                                              modality: 'CT',
                                            );
                                        await DatabaseService.instance.logAudit(
                                          'IMAGE_CAPTURED',
                                          imageId,
                                        );
                                        await _loadOrders();
                                        await _loadAudit();
                                        if (selectedPatient != null) {
                                          await _loadCapturedImages(
                                            selectedPatient!.patientID,
                                          );
                                        }
                                      },
                                      child: const Text('Capture'),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Models
class AuditEvent {
  final int eventId;
  final String time;
  final String eventType;
  final String refId;
  AuditEvent({
    required this.eventId,
    required this.time,
    required this.eventType,
    required this.refId,
  });
  factory AuditEvent.fromMap(Map<String, dynamic> m) => AuditEvent(
    eventId: m['EventID'],
    time: m['Time'],
    eventType: m['EventType'],
    refId: m['RefID'],
  );
}

class OrderModel {
  final String orderId, patientId, patientName, procedureCode, orderDateTime;
  OrderModel({
    required this.orderId,
    required this.patientId,
    required this.patientName,
    required this.procedureCode,
    required this.orderDateTime,
  });
  factory OrderModel.fromMap(Map<String, dynamic> m) => OrderModel(
    orderId: m['OrderID'],
    patientId: m['PatientID'],
    patientName: '${m['FirstName']} ${m['LastName']}',
    procedureCode: m['ProcedureCode'],
    orderDateTime: m['OrderDateTime'],
  );
}

class Patient {
  final String patientID, mrn, firstName, lastName, dob, gender, allergies;
  Patient({
    required this.patientID,
    required this.mrn,
    required this.firstName,
    required this.lastName,
    required this.dob,
    required this.gender,
    required this.allergies,
  });
  factory Patient.fromMap(Map<String, dynamic> m) => Patient(
    patientID: m['PatientID'],
    mrn: m['MRN'],
    firstName: m['FirstName'],
    lastName: m['LastName'],
    dob: m['DOB'],
    gender: m['Gender'],
    allergies: m['Allergies'],
  );
}

class ImageModel {
  final String imageId, orderId, patientId, filePath, studyDate, modality;
  ImageModel({
    required this.imageId,
    required this.orderId,
    required this.patientId,
    required this.filePath,
    required this.studyDate,
    required this.modality,
  });
  factory ImageModel.fromMap(Map<String, dynamic> m) => ImageModel(
    imageId: m['ImageID'],
    orderId: m['OrderID'],
    patientId: m['PATIENTID'] ?? m['PatientID'], // fallback
    filePath: m['FilePath'],
    studyDate: m['StudyDate'],
    modality: m['Modality'],
  );
}

// DatabaseService
class DatabaseService {
  DatabaseService._();
  static final instance = DatabaseService._();
  late final DatabaseFactory _factory = databaseFactoryFfi;
  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    sqfliteFfiInit();
    final dbDir = Directory(p.join(Directory.current.path, 'data', 'db'));
    if (!await dbDir.exists()) await dbDir.create(recursive: true);
    final path = p.join(dbDir.path, 'order2image.sqlite');
    _db = await _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1, onCreate: _createSchema),
    );
    return _db!;
  }

  Future _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE Patient (
        PatientID TEXT PRIMARY KEY,
        MRN TEXT,
        EncounterID TEXT,
        FirstName TEXT,
        LastName TEXT,
        DOB TEXT,
        Gender TEXT,
        Allergies TEXT
      );
    ''');
    await db.execute('''
      CREATE TABLE "Order" (
        OrderID TEXT PRIMARY KEY,
        PatientID TEXT,
        ProcedureCode TEXT,
        OrderDateTime TEXT,
        FOREIGN KEY(PatientID) REFERENCES Patient(PatientID)
      );
    ''');
    await db.execute('''
      CREATE TABLE Image (
        ImageID TEXT PRIMARY KEY,
        OrderID TEXT,
        PatientID TEXT,
        FilePath TEXT,
        StudyDate TEXT,
        Modality TEXT,
        FOREIGN KEY(PatientID) REFERENCES Patient(PatientID),
        FOREIGN KEY(OrderID) REFERENCES "Order"(OrderID)
      );
    ''');
    await db.execute('''
      CREATE TABLE Audit (
        EventID INTEGER PRIMARY KEY AUTOINCREMENT,
        Time TEXT,
        EventType TEXT,
        RefID TEXT
      );
    ''');

    // seed patients
    await db.insert('Patient', {
      'PatientID': 'P1001',
      'MRN': '1001',
      'EncounterID': 'E2001',
      'FirstName': 'Alice',
      'LastName': 'Smith',
      'DOB': '1975-02-15',
      'Gender': 'F',
      'Allergies': 'Penicillin',
    });
    await db.insert('Patient', {
      'PatientID': 'P1002',
      'MRN': '1002',
      'EncounterID': 'E2002',
      'FirstName': 'Bob',
      'LastName': 'Jones',
      'DOB': '1982-07-30',
      'Gender': 'M',
      'Allergies': 'Iodine Contrast',
    });
    await db.insert('Patient', {
      'PatientID': 'P1003',
      'MRN': '1003',
      'EncounterID': 'E2003',
      'FirstName': 'Carol',
      'LastName': 'Lee',
      'DOB': '1990-11-05',
      'Gender': 'F',
      'Allergies': '',
    });
  }

  Future<List<Map<String, dynamic>>> getAllPatients() async {
    return await (await db).query('Patient', orderBy: 'LastName, FirstName');
  }

  Future<void> insertOrder({
    required String orderId,
    required String patientId,
    required String procedureCode,
    required String orderDateTime,
  }) async {
    await (await db).insert('Order', {
      'OrderID': orderId,
      'PatientID': patientId,
      'ProcedureCode': procedureCode,
      'OrderDateTime': orderDateTime,
    });
  }

  Future<void> insertImage({
    required String imageId,
    required String orderId,
    required String patientId,
    required String filePath,
    required String studyDate,
    required String modality,
  }) async {
    await (await db).insert('Image', {
      'ImageID': imageId,
      'OrderID': orderId,
      'PatientID': patientId,
      'FilePath': filePath,
      'StudyDate': studyDate,
      'Modality': modality,
    });
  }

  Future<void> logAudit(String eventType, String refId) async {
    await (await db).insert('Audit', {
      'Time': DateTime.now().toIso8601String(),
      'EventType': eventType,
      'RefID': refId,
    });
  }

  Future<List<OrderModel>> getPendingOrders() async {
    final rows = await (await db).rawQuery('''
      SELECT o.OrderID, o.PatientID, o.ProcedureCode, o.OrderDateTime,
             p.FirstName, p.LastName
      FROM "Order" o
      JOIN Patient p ON o.PatientID = p.PatientID
      LEFT JOIN Image i ON o.OrderID = i.OrderID
      WHERE i.ImageID IS NULL
      ORDER BY o.OrderDateTime DESC
    ''');
    return rows.map((m) => OrderModel.fromMap(m)).toList();
  }

  Future<List<AuditEvent>> getAuditLog() async {
    final rows = await (await db).query(
      'Audit',
      orderBy: 'Time ASC',
      limit: 100,
    );
    return rows.map((m) => AuditEvent.fromMap(m)).toList();
  }

  Future<List<ImageModel>> getImagesByPatient(String patientId) async {
    final rows = await (await db).query(
      'Image',
      where: 'PatientID = ?',
      whereArgs: [patientId],
      orderBy: 'StudyDate ASC',
    );
    return rows.map((m) => ImageModel.fromMap(m)).toList();
  }
}
