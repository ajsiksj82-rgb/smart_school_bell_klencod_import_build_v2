import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/lesson_progress_models.dart';
import '../repositories/schedule_day_provider.dart';
import 'progress_calculator.dart';

/// يدير التحديث التلقائي لبطاقة تقدم الحصة.
///
/// - لا يحفظ أي نسبة قديمة: كل تحديث يُحسب من الساعة الحالية.
/// - يتوقف المؤقّت عند خروج التطبيق من الواجهة، ويعيد تحميل اليوم عند العودة.
/// - أثناء الحصة يحدّث كل ثانية، وخارجها كل 30 ثانية كحد أقصى (توفيرًا للبطارية).
class LessonProgressController with WidgetsBindingObserver {
  LessonProgressController(
    this._provider, {
    DateTime Function()? clock,
    Duration overdueWindow = ProgressCalculator.defaultOverdueWindow,
  })  : _clock = clock ?? DateTime.now,
        _overdueWindow = overdueWindow;

  final ScheduleDayProvider _provider;
  final DateTime Function() _clock;
  final Duration _overdueWindow;

  /// null = لم تُحمَّل البيانات بعد (أو حدث خطأ، راجع [lastError]).
  final ValueNotifier<ProgressSnapshot?> snapshot = ValueNotifier(null);
  Object? lastError;

  int? _buildingId;
  DayScheduleResult? _day;
  DaySegment? _futureNext;
  bool _futureSearched = false;
  final Map<int, bool> _executed = {};
  DateTime _lastExecCheck = DateTime.fromMillisecondsSinceEpoch(0);

  Timer? _timer;
  StreamSubscription<void>? _sub;
  bool _active = false;
  bool _started = false;
  int _gen = 0;

  void start() {
    if (_started) return;
    _started = true;
    _active = true;
    WidgetsBinding.instance.addObserver(this);
    _sub = _provider.changes.listen((_) => unawaited(_reload()));
    unawaited(_reload());
  }

  /// يُستدعى عند اختيار مدرسة/مبنى آخر.
  void setBuilding(int buildingId) {
    if (_buildingId == buildingId) return;
    _buildingId = buildingId;
    _day = null;
    snapshot.value = null;
    if (_started) unawaited(_reload());
  }

  /// يُستدعى بعد أي تعديل للجدول إن لم تُستخدم إشارة [ScheduleDayProvider.changes].
  void refresh() => unawaited(_reload());

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _active = true;
        // الوقت أو المنطقة الزمنية أو الجدول قد تغيّر أثناء الغياب.
        unawaited(_reload());
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _active = false;
        _timer?.cancel();
      case AppLifecycleState.inactive:
        break;
    }
  }

  Future<void> _reload() async {
    final id = _buildingId;
    if (id == null) return;
    final gen = ++_gen;
    _timer?.cancel();
    final now = _clock();
    try {
      final day = await _provider.loadDay(id, DateTime(now.year, now.month, now.day));
      if (gen != _gen) return;
      _day = day;
      _executed.clear();
      _futureNext = null;
      _futureSearched = false;
      lastError = null;
    } catch (e) {
      if (gen != _gen) return;
      lastError = e;
      snapshot.value = null;
      if (_active) {
        _timer = Timer(const Duration(seconds: 5), () => unawaited(_reload()));
      }
      return;
    }
    await _tick();
  }

  Future<void> _tick() async {
    _timer?.cancel();
    final id = _buildingId;
    if (!_active || id == null) return;
    final gen = _gen;
    var now = _clock();
    final day = _day;

    // تغيّر اليوم (منتصف الليل أو تغيير الساعة): أعد التحميل.
    if (day == null || !_sameDate(day.date, now)) {
      await _reload();
      return;
    }

    // هل انتهت فترة قبل لحظات؟ تحقق من سجل تنفيذ جرس نهايتها.
    final cand =
        ProgressCalculator.recentlyEnded(now, day, window: _overdueWindow);
    if (cand != null &&
        _executed[cand.endEventId!] != true &&
        now.difference(_lastExecCheck) >= const Duration(seconds: 2)) {
      _lastExecCheck = now;
      try {
        final ok = await _provider.wasBellExecuted(id, cand.endEventId!, day.date);
        if (gen != _gen) return;
        _executed[cand.endEventId!] = ok;
      } catch (_) {
        if (gen != _gen) return;
      }
      now = _clock();
    }

    var snap = _compute(now, day);

    if (_needsFuture(snap) && !_futureSearched) {
      _futureSearched = true;
      _futureNext = await _findNextUpcoming(id, now, day);
      if (gen != _gen) return;
      now = _clock();
      snap = _compute(now, day);
    }

    snapshot.value = snap;
    _timer = Timer(_nextDelay(snap, now), () => unawaited(_tick()));
  }

  ProgressSnapshot _compute(DateTime now, DayScheduleResult day) {
    return ProgressCalculator.compute(
      now: now,
      day: day,
      nextOverride: _futureNext,
      overdueWindow: _overdueWindow,
      bellExecuted: (s) => s.endEventId != null && _executed[s.endEventId!] == true,
    );
  }

  bool _needsFuture(ProgressSnapshot s) =>
      s.next == null &&
      (s.phase == ProgressPhase.afterDay ||
          s.phase == ProgressPhase.holiday ||
          s.phase == ProgressPhase.nonWorkingDay ||
          s.phase == ProgressPhase.noSchedule);

  /// أول حصة قادمة خلال 14 يومًا (مع احترام الإجازات وأيام عدم الدوام).
  Future<DaySegment?> _findNextUpcoming(
      int buildingId, DateTime now, DayScheduleResult today) async {
    for (var i = 0; i <= 14; i++) {
      final date = DateTime(now.year, now.month, now.day + i);
      final DayScheduleResult r;
      try {
        r = i == 0 ? today : await _provider.loadDay(buildingId, date);
      } catch (_) {
        return null;
      }
      if (r.status != DayStatus.working) continue;
      for (final s in r.segments) {
        if (s.kind == SegmentKind.lesson && s.start.isAfter(now)) return s;
      }
    }
    return null;
  }

  Duration _nextDelay(ProgressSnapshot s, DateTime now) {
    // أثناء الحصة (أو التجاوز): كل ثانية، متزامنًا مع حدود الثواني.
    if (s.current != null) {
      return Duration(milliseconds: 1000 - now.millisecond);
    }
    var d = const Duration(seconds: 30);
    final n = s.next;
    if (n != null) {
      final u = n.start.difference(now);
      if (!u.isNegative && u < d) d = u;
    }
    final midnight = DateTime(now.year, now.month, now.day + 1).difference(now);
    if (midnight < d) d = midnight;
    const floor = Duration(milliseconds: 200);
    return d < floor ? floor : d;
  }

  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    snapshot.dispose();
  }
}
