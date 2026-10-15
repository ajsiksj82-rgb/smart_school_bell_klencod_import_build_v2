import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class AppDatabase {
  late final Database database;

  Future<void> open() async {
    final root = await getDatabasesPath();
    database = await openDatabase(
      p.join(root, 'smart_school_bell.db'),
      version: 1,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE schools(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)''');
        await db.execute('''CREATE TABLE buildings(id INTEGER PRIMARY KEY AUTOINCREMENT, school_id INTEGER NOT NULL, name TEXT NOT NULL, FOREIGN KEY(school_id) REFERENCES schools(id) ON DELETE CASCADE)''');
        await db.execute('''CREATE TABLE schedules(id INTEGER PRIMARY KEY AUTOINCREMENT, building_id INTEGER NOT NULL, day_of_week INTEGER NOT NULL, is_working INTEGER NOT NULL DEFAULT 1, UNIQUE(building_id, day_of_week), FOREIGN KEY(building_id) REFERENCES buildings(id) ON DELETE CASCADE)''');
        await db.execute('''CREATE TABLE bell_events(id INTEGER PRIMARY KEY AUTOINCREMENT, schedule_id INTEGER NOT NULL, event_type TEXT NOT NULL, event_time TEXT NOT NULL, label TEXT, subject TEXT, is_enabled INTEGER NOT NULL DEFAULT 1, FOREIGN KEY(schedule_id) REFERENCES schedules(id) ON DELETE CASCADE)''');
        await db.execute('''CREATE TABLE holidays(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, start_date TEXT NOT NULL, end_date TEXT NOT NULL, school_id INTEGER NOT NULL, building_id INTEGER, is_active INTEGER NOT NULL DEFAULT 1, FOREIGN KEY(school_id) REFERENCES schools(id) ON DELETE CASCADE, FOREIGN KEY(building_id) REFERENCES buildings(id) ON DELETE CASCADE)''');
        await db.execute('''CREATE TABLE execution_logs(id INTEGER PRIMARY KEY AUTOINCREMENT, building_id INTEGER NOT NULL, event_id INTEGER, scheduled_date TEXT NOT NULL, result TEXT NOT NULL, message TEXT, executed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY(building_id) REFERENCES buildings(id) ON DELETE CASCADE)''');
        await db.execute('''CREATE TABLE app_settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
      },
    );
    final existing = await database.query('schools', limit: 1);
    if (existing.isEmpty) {
      final schoolId = await database.insert('schools', {'name': 'مدرستي'});
      final buildingId = await database.insert('buildings', {'school_id': schoolId, 'name': 'المبنى الرئيسي'});
      for (var day = 1; day <= 7; day++) {
        await database.insert('schedules', {'building_id': buildingId, 'day_of_week': day, 'is_working': day <= 5 ? 1 : 0});
      }
    }
  }

  Future<List<Map<String, Object?>>> buildings() => database.rawQuery('''SELECT b.id, b.name AS building_name, b.school_id, s.name AS school_name FROM buildings b JOIN schools s ON s.id=b.school_id ORDER BY s.name,b.name''');
  Future<List<Map<String, Object?>>> schools() => database.query('schools', orderBy: 'name');
  Future<void> addSchool(String name) async { final value=name.trim(); if(value.isNotEmpty) await database.insert('schools', {'name':value}); }

  Future<void> addBuilding(int schoolId, String name) async {
    final value=name.trim(); if(value.isEmpty)return;
    final id=await database.insert('buildings', {'school_id':schoolId,'name':value});
    for(var day=1;day<=7;day++){await database.insert('schedules', {'building_id':id,'day_of_week':day,'is_working':day<=5?1:0});}
  }

  Future<bool> isWorkingDay(int buildingId, int weekday) async {
    final rows = await database.query('schedules', columns: ['is_working'], where: 'building_id=? AND day_of_week=?', whereArgs: [buildingId, weekday], limit: 1);
    return rows.isNotEmpty && (rows.first['is_working'] as int? ?? 1) == 1;
  }

  Future<bool> isHoliday(int buildingId, DateTime date) async {
    final ymd='${date.year.toString().padLeft(4,'0')}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';
    final rows=await database.rawQuery('''SELECT h.id FROM holidays h JOIN buildings b ON b.id=? WHERE h.is_active=1 AND h.start_date<=? AND h.end_date>=? AND (h.building_id=? OR (h.building_id IS NULL AND h.school_id=b.school_id)) LIMIT 1''',[buildingId,ymd,ymd,buildingId]);
    return rows.isNotEmpty;
  }

  Future<List<Map<String, Object?>>> events(int buildingId, int weekday) async {
    final rows=await database.query('schedules',columns:['id'],where:'building_id=? AND day_of_week=?',whereArgs:[buildingId,weekday],limit:1);
    if(rows.isEmpty)return [];
    return database.query('bell_events',where:'schedule_id=?',whereArgs:[rows.first['id']],orderBy:'event_time ASC');
  }

  Future<void> addEvent({required int buildingId, required int weekday, required String type, required String time, required String label, String? subject}) async {
    final rows=await database.query('schedules',columns:['id'],where:'building_id=? AND day_of_week=?',whereArgs:[buildingId,weekday],limit:1);
    final int scheduleId;
    if(rows.isEmpty){scheduleId=await database.insert('schedules',{'building_id':buildingId,'day_of_week':weekday,'is_working':1});}
    else {scheduleId=rows.first['id'] as int; await database.update('schedules',{'is_working':1},where:'id=?',whereArgs:[scheduleId]);}
    await database.insert('bell_events',{'schedule_id':scheduleId,'event_type':type,'event_time':time,'label':label.trim().isEmpty?type:label.trim(),'subject':subject,'is_enabled':1});
  }
  Future<void> deleteEvent(int id) async { await database.delete('bell_events',where:'id=?',whereArgs:[id]); }
  Future<List<Map<String, Object?>>> holidays() => database.rawQuery('''SELECT h.*, s.name AS school_name FROM holidays h JOIN schools s ON s.id=h.school_id ORDER BY h.start_date DESC''');
  Future<void> addHoliday({required String title,required String start,required String end,required int schoolId}) async { await database.insert('holidays',{'title':title.trim(),'start_date':start,'end_date':end,'school_id':schoolId,'is_active':1}); }
  Future<void> deleteHoliday(int id) async { await database.delete('holidays',where:'id=?',whereArgs:[id]); }
  Future<List<Map<String, Object?>>> logs() => database.query('execution_logs',orderBy:'id DESC',limit:200);
  Future<bool> hasExecutedToday(int buildingId, int eventId, String date) async {
    final rows = await database.query('execution_logs', columns: ['id'], where: "building_id=? AND event_id=? AND scheduled_date=? AND result='success'", whereArgs: [buildingId, eventId, date], limit: 1);
    return rows.isNotEmpty;
  }
  Future<void> logBell({required int buildingId,int? eventId,required String result,required String message}) async {
    final now=DateTime.now(); final date='${now.year.toString().padLeft(4,'0')}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
    await database.insert('execution_logs',{'building_id':buildingId,'event_id':eventId,'scheduled_date':date,'result':result,'message':message});
  }
}
