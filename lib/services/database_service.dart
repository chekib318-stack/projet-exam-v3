import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class IncidentRecord {
  final int? id;
  final String deviceId;
  final String deviceName;
  final String deviceType;
  final double distance;
  final double rssi;
  final String threatLevel;
  final DateTime timestamp;
  final String session;
  final String? notes;

  const IncidentRecord({
    this.id,
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    required this.distance,
    required this.rssi,
    required this.threatLevel,
    required this.timestamp,
    required this.session,
    this.notes,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'device_id':   deviceId,
    'device_name': deviceName,
    'device_type': deviceType,
    'distance':    distance,
    'rssi':        rssi,
    'threat':      threatLevel,
    'timestamp':   timestamp.toIso8601String(),
    'session':     session,
    'notes':       notes,
  };

  factory IncidentRecord.fromMap(Map<String, dynamic> m) => IncidentRecord(
    id:         m['id'],
    deviceId:   m['device_id'],
    deviceName: m['device_name'],
    deviceType: m['device_type'],
    distance:   m['distance'],
    rssi:       m['rssi'],
    threatLevel: m['threat'],
    timestamp:  DateTime.parse(m['timestamp']),
    session:    m['session'],
    notes:      m['notes'],
  );
}

class DbService {
  static final DbService instance = DbService._();
  DbService._();
  Database? _db;

  Future<void> init() async {
    _db = await openDatabase(
      join(await getDatabasesPath(), 'examguard_v2.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE incidents (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id  TEXT NOT NULL,
            device_name TEXT NOT NULL,
            device_type TEXT NOT NULL,
            distance   REAL NOT NULL,
            rssi       REAL NOT NULL,
            threat     TEXT NOT NULL,
            timestamp  TEXT NOT NULL,
            session    TEXT NOT NULL,
            notes      TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE whitelist (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id  TEXT UNIQUE NOT NULL,
            label      TEXT,
            added_at   TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<int> insertIncident(IncidentRecord r) =>
      _db!.insert('incidents', r.toMap());

  Future<List<IncidentRecord>> getIncidents({String? session}) async {
    final rows = await _db!.query(
      'incidents',
      where: session != null ? 'session = ?' : null,
      whereArgs: session != null ? [session] : null,
      orderBy: 'timestamp DESC',
    );
    return rows.map(IncidentRecord.fromMap).toList();
  }

  Future<void> clearIncidents(String session) =>
      _db!.delete('incidents', where: 'session = ?', whereArgs: [session]);

  Future<void> addWhitelist(String id, String label) =>
      _db!.insert('whitelist', {
        'device_id': id, 'label': label,
        'added_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> removeWhitelist(String id) =>
      _db!.delete('whitelist', where: 'device_id = ?', whereArgs: [id]);

  Future<List<Map<String, dynamic>>> getWhitelist() =>
      _db!.query('whitelist', orderBy: 'added_at DESC');
}
