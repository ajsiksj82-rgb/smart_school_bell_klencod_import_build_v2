import 'dart:async';

import '../features/lesson_progress/models/lesson_progress_models.dart';
import '../features/lesson_progress/repositories/schedule_day_provider.dart';

/// مزوّد بيانات تجريبي في الذاكرة لمعاينة الميزة دون قاعدة بيانات.
/// يبني حصة بدأت قبل 10 دقائق، ثم استراحة، ثم حصة ثانية.
/// استبدله بـ SqliteScheduleDayProvider في التطبيق الفعلي.
class DemoScheduleProvider implements ScheduleDayProvider {
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<DayScheduleResult> loadDay(int buildingId, DateTime date) async {
    final now = DateTime.now();
    final day = DateTime(date.year, date.month, date.day);
    if (day != DateTime(now.year, now.month, now.day)) {
      return DayScheduleResult(date: day, status: DayStatus.nonWorkingDay);
    }
    final t0 = DateTime(now.year, now.month, now.day, now.hour, now.minute)
        .subtract(const Duration(minutes: 10));
    final l1End = t0.add(const Duration(minutes: 45));
    final brEnd = l1End.add(const Duration(minutes: 15));
    final l2End = brEnd.add(const Duration(minutes: 45));
    return DayScheduleResult(
      date: day,
      status: DayStatus.working,
      segments: [
        DaySegment(
            kind: SegmentKind.lesson,
            name: 'الحصة 1',
            number: 1,
            subject: 'الحاسوب',
            start: t0,
            end: l1End,
            endEventId: 1),
        DaySegment(
            kind: SegmentKind.breakTime,
            name: 'الاستراحة',
            start: l1End,
            end: brEnd,
            endEventId: 2),
        DaySegment(
            kind: SegmentKind.lesson,
            name: 'الحصة 2',
            number: 2,
            subject: 'اللغة العربية',
            start: brEnd,
            end: l2End,
            endEventId: 3),
      ],
    );
  }

  @override
  Future<bool> wasBellExecuted(int buildingId, int eventId, DateTime date) async =>
      false;
}
