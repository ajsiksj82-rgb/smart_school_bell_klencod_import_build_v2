import '../models/lesson_progress_models.dart';

enum ProgressPhase {
  inSegment,
  overdue,
  gap,
  beforeDay,
  afterDay,
  holiday,
  nonWorkingDay,
  noSchedule,
}

class ProgressSnapshot {
  const ProgressSnapshot({
    required this.now,
    required this.phase,
    this.current,
    this.next,
    this.holidayName,
    this.fraction = 0,
    this.elapsed = Duration.zero,
    this.remaining = Duration.zero,
    this.overrun = Duration.zero,
    this.nearEnd = false,
  });

  final DateTime now;
  final ProgressPhase phase;

  /// الفترة المعروضة (الحالية، أو التي تجاوزت وقتها في حالة overdue).
  final DaySegment? current;
  final DaySegment? next;
  final String? holidayName;

  /// من 0.0 إلى 1.0 محسوبة من الوقت الفعلي.
  final double fraction;
  final Duration elapsed;
  final Duration remaining;
  final Duration overrun;
  final bool nearEnd;

  /// يُقرَّب للأسفل كي لا تظهر 100% قبل نهاية الحصة فعلًا.
  int get percent => (fraction * 100).floor().clamp(0, 100);
}

/// منطق صرف بلا واجهات ولا قاعدة بيانات، لسهولة الاختبار.
class ProgressCalculator {
  static const Duration defaultOverdueWindow = Duration(minutes: 5);

  /// نسبة التقدم = (الآن − البداية) ÷ (النهاية − البداية)، ضمن [0, 1].
  static double fractionOf(DateTime now, DateTime start, DateTime end) {
    final total = end.difference(start).inMilliseconds;
    if (total <= 0) return 1;
    final done = now.difference(start).inMilliseconds;
    return (done / total).clamp(0.0, 1.0);
  }

  /// آخر فترة انتهت حديثًا ولم تبدأ فترة بعدها، وجرس نهايتها مُنتظر.
  static DaySegment? recentlyEnded(
    DateTime now,
    DayScheduleResult day, {
    Duration window = defaultOverdueWindow,
  }) {
    if (day.status != DayStatus.working) return null;
    DaySegment? prev;
    for (final s in day.segments) {
      if (!s.start.isAfter(now) && s.end.isAfter(now)) return null;
      if (!s.end.isAfter(now)) prev = s;
    }
    if (prev == null) return null;
    if (now.difference(prev.end) >= window) return null;
    if (!prev.endBellEnabled || prev.endEventId == null) return null;
    return prev;
  }

  static ProgressSnapshot compute({
    required DateTime now,
    required DayScheduleResult day,
    bool Function(DaySegment segment)? bellExecuted,
    DaySegment? nextOverride,
    Duration overdueWindow = defaultOverdueWindow,
  }) {
    switch (day.status) {
      case DayStatus.holiday:
        return ProgressSnapshot(
          now: now,
          phase: ProgressPhase.holiday,
          holidayName: day.holidayName,
          next: nextOverride,
        );
      case DayStatus.nonWorkingDay:
        return ProgressSnapshot(
            now: now, phase: ProgressPhase.nonWorkingDay, next: nextOverride);
      case DayStatus.noSchedule:
        return ProgressSnapshot(
            now: now, phase: ProgressPhase.noSchedule, next: nextOverride);
      case DayStatus.working:
        break;
    }

    final segs = day.segments;
    if (segs.isEmpty) {
      return ProgressSnapshot(
          now: now, phase: ProgressPhase.noSchedule, next: nextOverride);
    }

    // داخل فترة؟
    for (var i = 0; i < segs.length; i++) {
      final s = segs[i];
      if (!now.isBefore(s.start) && now.isBefore(s.end)) {
        final remaining = s.end.difference(now);
        final warnAt = _min(const Duration(minutes: 5),
            Duration(milliseconds: (s.total.inMilliseconds * 0.2).round()));
        return ProgressSnapshot(
          now: now,
          phase: ProgressPhase.inSegment,
          current: s,
          next: i + 1 < segs.length ? segs[i + 1] : nextOverride,
          fraction: fractionOf(now, s.start, s.end),
          elapsed: now.difference(s.start),
          remaining: remaining,
          nearEnd: remaining <= warnAt,
        );
      }
    }

    DaySegment? prev;
    DaySegment? next;
    for (final s in segs) {
      if (!s.end.isAfter(now)) prev = s;
      if (next == null && s.start.isAfter(now)) next = s;
    }

    // تجاوز وقت النهاية دون تنفيذ الجرس.
    final late = bellExecuted == null
        ? null
        : recentlyEnded(now, day, window: overdueWindow);
    if (late != null && !bellExecuted!(late)) {
      return ProgressSnapshot(
        now: now,
        phase: ProgressPhase.overdue,
        current: late,
        next: next,
        fraction: 1,
        elapsed: late.total,
        overrun: now.difference(late.end),
      );
    }

    if (prev == null) {
      return ProgressSnapshot(
          now: now, phase: ProgressPhase.beforeDay, next: next);
    }
    if (next == null) {
      return ProgressSnapshot(
          now: now, phase: ProgressPhase.afterDay, next: nextOverride);
    }
    return ProgressSnapshot(now: now, phase: ProgressPhase.gap, next: next);
  }

  static Duration _min(Duration a, Duration b) => a < b ? a : b;
}
