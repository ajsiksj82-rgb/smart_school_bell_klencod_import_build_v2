import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/app_database.dart';
import 'features/lesson_progress/repositories/schedule_day_provider.dart';
import 'features/lesson_progress/services/lesson_progress_controller.dart';
import 'features/lesson_progress/widgets/lesson_progress_card.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase();
  await database.open();
  runApp(SmartSchoolBellApp(database: database));
}

class SmartSchoolBellApp extends StatelessWidget {
  const SmartSchoolBellApp({super.key, required this.database});
  final AppDatabase database;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'الجرس المدرسي الذكي', debugShowCheckedModeBanner: false,
    locale: const Locale('ar'), supportedLocales: const [Locale('ar')],
    localizationsDelegates: const [GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
    theme: ThemeData(colorSchemeSeed: const Color(0xFF174A7E),
      scaffoldBackgroundColor: const Color(0xFFF4F6FA), useMaterial3: true),
    home: MainShell(database: database),
  );
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.database});
  final AppDatabase database;
  @override State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int tab = 0;
  @override Widget build(BuildContext context) {
    final pages = [
      HomePage(database: widget.database),
      SchoolsPage(database: widget.database),
      SchedulePage(database: widget.database),
      HolidaysPage(database: widget.database),
      LogsPage(database: widget.database),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: tab, children: pages)),
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab=v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.apartment), label: 'المدارس'),
          NavigationDestination(icon: Icon(Icons.schedule), label: 'الجدول'),
          NavigationDestination(icon: Icon(Icons.event_busy), label: 'الإجازات'),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'السجل'),
        ]),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.database});
  final AppDatabase database;
  @override State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  List<Map<String,Object?>> buildings=[];
  int? selectedBuilding;
  LessonProgressController? controller;
  bool loading=true;
  Timer? _scheduleTimer;
  bool _checkingSchedule=false;
  final Set<String> _firedThisSession={};
  @override void initState(){super.initState(); _load(); _scheduleTimer=Timer.periodic(const Duration(seconds:5), (_) => _checkScheduledEvents());}
  Future<void> _load() async {
    final rows=await widget.database.buildings();
    if(!mounted)return;
    setState(() { buildings=rows; selectedBuilding ??= rows.isNotEmpty ? rows.first['id'] as int : null; loading=false; });
    if(selectedBuilding!=null && controller==null){
      controller=LessonProgressController(SqliteScheduleDayProvider(widget.database.database))..start()..setBuilding(selectedBuilding!);
      setState((){});
    }
  }
  @override void dispose(){_scheduleTimer?.cancel();controller?.dispose();super.dispose();}
  Future<void> _checkScheduledEvents() async {
    if (_checkingSchedule || selectedBuilding==null || !mounted) return;
    final now=DateTime.now();
    // Foreground-only best effort: run shortly after the minute boundary. This is not an Android background alarm.
    if(now.second>7) return;
    _checkingSchedule=true;
    try {
      if (await widget.database.isHoliday(selectedBuilding!, now) || !await widget.database.isWorkingDay(selectedBuilding!, now.weekday)) return;
      final rows=await widget.database.events(selectedBuilding!,now.weekday);
      final hh='${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';
      final date='${now.year.toString().padLeft(4,'0')}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
      for(final e in rows){
        if((e['is_enabled'] as int? ?? 1)!=1 || e['event_time']!=hh) continue;
        final id=e['id'] as int; final key='$date:$selectedBuilding:$id';
        if(_firedThisSession.contains(key) || await widget.database.hasExecutedToday(selectedBuilding!,id,date)) continue;
        await SystemSound.play(SystemSoundType.alert);
        await widget.database.logBell(buildingId:selectedBuilding!,eventId:id,result:'success',message:'${e['label']??e['event_type']} — تشغيل مجدول أثناء فتح التطبيق');
        _firedThisSession.add(key);
      }
    } catch (_) { /* يسجل المستخدم الأعطال عند التشغيل اليدوي؛ لا نوقف الواجهة بسبب فشل الفحص */ }
    finally { _checkingSchedule=false; }
  }
  Future<void> _ring() async {
    try {
      await SystemSound.play(SystemSoundType.alert);
      if(selectedBuilding!=null) await widget.database.logBell(buildingId:selectedBuilding!,result:'success',message:'تشغيل الجرس يدويًا (تنبيه النظام)');
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم طلب تشغيل صوت التنبيه من النظام')));
    } catch(e) {
      if(selectedBuilding!=null) await widget.database.logBell(buildingId:selectedBuilding!,result:'failed',message:'تعذر تشغيل الصوت: $e');
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('تعذر تشغيل الصوت: $e')));
    }
  }
  @override Widget build(BuildContext context){
    if(loading)return const Center(child:CircularProgressIndicator());
    Map<String,Object?>? current;
    for (final b in buildings) { if (b['id']==selectedBuilding) { current=b; break; } }
    return Scaffold(appBar:AppBar(title:const Text('الجرس المدرسي الذكي'), actions:[IconButton(tooltip:'تحديث',onPressed:_load,icon:const Icon(Icons.refresh))]),
      body:RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.all(16),children:[
        Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('المدرسة والمبنى النشطان',style:TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:8),
          DropdownButtonFormField<int>(value:selectedBuilding, isExpanded:true, decoration:const InputDecoration(border:OutlineInputBorder(),prefixIcon:Icon(Icons.location_city)),
            items:buildings.map((b)=>DropdownMenuItem(value:b['id'] as int,child:Text('${b['school_name']} — ${b['building_name']}'))).toList(),
            onChanged:(v){setState(()=>selectedBuilding=v);if(v!=null){controller?.setBuilding(v);if(controller==null)_load();}}),
          const SizedBox(height:8),Text(current==null?'أضف مدرسة ومبنى من تبويب المدارس.':'المتابعة الزمنية مرتبطة بالجدول المحفوظ محليًا.',style:Theme.of(context).textTheme.bodySmall),
        ]))),
        if(controller!=null) LessonProgressCard(controller:controller!) else const Card(child:Padding(padding:EdgeInsets.all(20),child:Text('لا توجد مبانٍ حتى الآن. أضف مدرسة ومبنى للبدء.'))),
        const SizedBox(height:12),
        SizedBox(height:58,child:FilledButton.icon(onPressed:selectedBuilding==null?null:_ring,icon:const Icon(Icons.notifications_active),label:const Text('تشغيل الجرس يدويًا'))),
        const SizedBox(height:12),
        const Card(child:Padding(padding:EdgeInsets.all(14),child:Text('تنبيه: التشغيل اليدوي يستخدم تنبيه النظام الافتراضي. الجدولة التلقائية أثناء إغلاق التطبيق تحتاج تكامل Android واختبارًا على الهاتف.',style:TextStyle(color:Colors.deepOrange)))),
      ])));
  }
}

class SchoolsPage extends StatefulWidget { const SchoolsPage({super.key,required this.database}); final AppDatabase database; @override State<SchoolsPage> createState()=>_SchoolsPageState(); }
class _SchoolsPageState extends State<SchoolsPage>{
  List<Map<String,Object?>> schools=[], buildings=[]; bool loading=true;
  @override void initState(){super.initState();_refresh();}
  Future<void> _refresh() async {schools=await widget.database.schools();buildings=await widget.database.buildings();if(mounted)setState(()=>loading=false);}
  Future<String?> _textDialog(String title,String label) async {final c=TextEditingController();final r=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:Text(title),content:TextField(controller:c,autofocus:true,decoration:InputDecoration(labelText:label)),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,c.text),child:const Text('حفظ'))]));c.dispose();return r;}
  Future<void> _addSchool() async {final n=await _textDialog('إضافة مدرسة','اسم المدرسة');if(n!=null&&n.trim().isNotEmpty){await widget.database.addSchool(n);await _refresh();}}
  Future<void> _addBuilding() async {if(schools.isEmpty){await _addSchool();if(schools.isEmpty)return;}int sid=schools.first['id'] as int;final name=TextEditingController();final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(title:const Text('إضافة مبنى'),content:Column(mainAxisSize:MainAxisSize.min,children:[DropdownButtonFormField<int>(value:sid,decoration:const InputDecoration(labelText:'المدرسة'),items:schools.map((s)=>DropdownMenuItem(value:s['id'] as int,child:Text(s['name'] as String))).toList(),onChanged:(v){if(v!=null)setD(()=>sid=v);}),TextField(controller:name,decoration:const InputDecoration(labelText:'اسم المبنى'))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('حفظ'))])));if(ok==true&&name.text.trim().isNotEmpty){await widget.database.addBuilding(sid,name.text);await _refresh();}name.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('إدارة المدارس والمباني'),actions:[IconButton(onPressed:_refresh,icon:const Icon(Icons.refresh))]),floatingActionButton:PopupMenuButton<String>(icon:const Icon(Icons.add_circle,size:54),itemBuilder:(_)=>const [PopupMenuItem(value:'school',child:Text('إضافة مدرسة')),PopupMenuItem(value:'building',child:Text('إضافة مبنى'))],onSelected:(v)=>v=='school'?_addSchool():_addBuilding()),body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(12),children:[const Text('المدارس',style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)),...schools.map((s)=>Card(child:ListTile(leading:const Icon(Icons.school),title:Text(s['name'] as String),subtitle:Text('${buildings.where((b)=>b['school_id']==s['id']).length} مبنى')))),const Divider(),const Text('المباني',style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)),...buildings.map((b)=>Card(child:ListTile(leading:const Icon(Icons.apartment),title:Text(b['building_name'] as String),subtitle:Text(b['school_name'] as String))))]));
}

class SchedulePage extends StatefulWidget {const SchedulePage({super.key,required this.database});final AppDatabase database;@override State<SchedulePage> createState()=>_SchedulePageState();}
class _SchedulePageState extends State<SchedulePage>{
  List<Map<String,Object?>> buildings=[];int? buildingId;int weekday=DateTime.now().weekday;List<Map<String,Object?>> events=[];bool loading=true;
  static const days=['','الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت','الأحد'];
  static const types={'dayStart':'بداية الدوام','assemblyStart':'الطابور','lessonStart':'بداية حصة','lessonEnd':'نهاية حصة','breakStart':'بداية الفسحة','breakEnd':'نهاية الفسحة','dayEnd':'نهاية الدوام'};
  @override void initState(){super.initState();_init();}
  Future<void> _init() async {buildings=await widget.database.buildings();buildingId ??=buildings.isNotEmpty?buildings.first['id'] as int:null;await _loadEvents();if(mounted)setState(()=>loading=false);}
  Future<void> _loadEvents() async {if(buildingId==null){events=[];return;}events=await widget.database.events(buildingId!,weekday);if(mounted)setState((){});}
  Future<void> _add() async {if(buildingId==null)return;String type='lessonStart';TimeOfDay time=const TimeOfDay(hour:8,minute:0);final label=TextEditingController();final subject=TextEditingController();final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(title:const Text('إضافة حدث للجدول'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[DropdownButtonFormField<String>(value:type,decoration:const InputDecoration(labelText:'نوع الحدث'),items:types.entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value))).toList(),onChanged:(v){if(v!=null)setD(()=>type=v);}),ListTile(title:const Text('وقت الجرس'),subtitle:Text(time.format(ctx)),trailing:const Icon(Icons.access_time),onTap:()async{final t=await showTimePicker(context:ctx,initialTime:time);if(t!=null)setD(()=>time=t);}),TextField(controller:label,decoration:const InputDecoration(labelText:'وصف الحدث (اختياري)')),TextField(controller:subject,decoration:const InputDecoration(labelText:'المادة (اختياري)'))])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('حفظ'))])));if(ok==true){final hh='${time.hour.toString().padLeft(2,'0')}:${time.minute.toString().padLeft(2,'0')}';await widget.database.addEvent(buildingId:buildingId!,weekday:weekday,type:type,time:hh,label:label.text,subject:subject.text);await _loadEvents();}label.dispose();subject.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('الجداول الدراسية'),actions:[IconButton(onPressed:_loadEvents,icon:const Icon(Icons.refresh))]),floatingActionButton:FloatingActionButton.extended(onPressed:_add,icon:const Icon(Icons.add),label:const Text('إضافة حدث')),body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(12),children:[DropdownButtonFormField<int>(value:buildingId,decoration:const InputDecoration(labelText:'المدرسة والمبنى',border:OutlineInputBorder()),items:buildings.map((b)=>DropdownMenuItem(value:b['id'] as int,child:Text('${b['school_name']} — ${b['building_name']}'))).toList(),onChanged:(v){setState(()=>buildingId=v);_loadEvents();}),const SizedBox(height:10),DropdownButtonFormField<int>(value:weekday,decoration:const InputDecoration(labelText:'اليوم',border:OutlineInputBorder()),items:List.generate(7,(i)=>DropdownMenuItem(value:i+1,child:Text(days[i+1]))),onChanged:(v){if(v!=null){setState(()=>weekday=v);_loadEvents();}}),const SizedBox(height:12),if(events.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(20),child:Text('لا توجد أحداث لهذا اليوم. استخدم «إضافة حدث» لإنشاء الجدول.'))),...events.map((e)=>Card(child:ListTile(leading:const Icon(Icons.notifications_active_outlined),title:Text('${e['event_time']} — ${e['label']??types[e['event_type']]??e['event_type']}'),subtitle:Text('${types[e['event_type']]??e['event_type']}${(e['subject'] as String? ?? '').isNotEmpty?' • ${e['subject']}':''}'),trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{await widget.database.deleteEvent(e['id'] as int);await _loadEvents();}))))]));
}

class HolidaysPage extends StatefulWidget {const HolidaysPage({super.key,required this.database});final AppDatabase database;@override State<HolidaysPage> createState()=>_HolidaysPageState();}
class _HolidaysPageState extends State<HolidaysPage>{List<Map<String,Object?>> schools=[],holidays=[];bool loading=true;@override void initState(){super.initState();_refresh();}Future<void> _refresh()async{schools=await widget.database.schools();holidays=await widget.database.holidays();if(mounted)setState(()=>loading=false);}String _date(DateTime d)=>'${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';Future<void> _add()async{if(schools.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('أضف مدرسة أولًا')));return;}final title=TextEditingController();int sid=schools.first['id'] as int;DateTime start=DateTime.now(),end=DateTime.now();final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(title:const Text('إضافة إجازة'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:title,decoration:const InputDecoration(labelText:'اسم الإجازة')),DropdownButtonFormField<int>(value:sid,decoration:const InputDecoration(labelText:'المدرسة'),items:schools.map((s)=>DropdownMenuItem(value:s['id'] as int,child:Text(s['name'] as String))).toList(),onChanged:(v){if(v!=null)setD(()=>sid=v);}),ListTile(title:const Text('من تاريخ'),subtitle:Text(_date(start)),onTap:()async{final d=await showDatePicker(context:ctx,initialDate:start,firstDate:DateTime(2020),lastDate:DateTime(2100));if(d!=null)setD(() { start=d; if(end.isBefore(start)) end=start; });}),ListTile(title:const Text('إلى تاريخ'),subtitle:Text(_date(end)),onTap:()async{final d=await showDatePicker(context:ctx,initialDate:end.isBefore(start)?start:end,firstDate:start,lastDate:DateTime(2100));if(d!=null)setD(()=>end=d);})]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('حفظ'))])));if(ok==true&&title.text.trim().isNotEmpty){await widget.database.addHoliday(title:title.text,start:_date(start),end:_date(end),schoolId:sid);await _refresh();}title.dispose();}@override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('الإجازات والعطل'),actions:[IconButton(onPressed:_refresh,icon:const Icon(Icons.refresh))]),floatingActionButton:FloatingActionButton.extended(onPressed:_add,icon:const Icon(Icons.add),label:const Text('إضافة إجازة')),body:loading?const Center(child:CircularProgressIndicator()):holidays.isEmpty?const Center(child:Text('لا توجد إجازات مسجلة')):ListView(padding:const EdgeInsets.all(12),children:holidays.map((h)=>Card(child:ListTile(leading:const Icon(Icons.event_busy),title:Text(h['title'] as String),subtitle:Text('${h['start_date']} إلى ${h['end_date']} • ${h['school_name']}'),trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{await widget.database.deleteHoliday(h['id'] as int);await _refresh();})))).toList()));}

class LogsPage extends StatefulWidget {const LogsPage({super.key,required this.database});final AppDatabase database;@override State<LogsPage> createState()=>_LogsPageState();}
class _LogsPageState extends State<LogsPage>{List<Map<String,Object?>> logs=[];@override void initState(){super.initState();_refresh();}Future<void> _refresh()async{logs=await widget.database.logs();if(mounted)setState((){});}@override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('سجل التشغيل'),actions:[IconButton(onPressed:_refresh,icon:const Icon(Icons.refresh))]),body:logs.isEmpty?const Center(child:Text('لا توجد أحداث مسجلة بعد')):ListView.builder(padding:const EdgeInsets.all(12),itemCount:logs.length,itemBuilder:(ctx,i){final r=logs[i];return Card(child:ListTile(leading:Icon(r['result']=='success'?Icons.check_circle_outline:Icons.error_outline,color:r['result']=='success'?Colors.green:Colors.red),title:Text(r['message'] as String? ?? 'حدث'),subtitle:Text('${r['scheduled_date']} • ${r['executed_at']}')));}));}