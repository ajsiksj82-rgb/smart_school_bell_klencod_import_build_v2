import 'package:flutter_test/flutter_test.dart';

import 'package:smart_school_bell/features/lesson_progress/models/lesson_progress_models.dart';
import 'package:smart_school_bell/features/lesson_progress/services/progress_calculator.dart';

void main() {
  final date = DateTime(2026, 10, 15);
  DateTime at(int h, int m, [int s = 0]) =>
      DateTime(date.year, date.month, date.day, h, m, s);

  // 08:00 بداية الدوام | حصة 1: 08:00–08:45 | استراحة 08:45–09:00
  // حصة 2: 09:00–09:45 | نهاية الدوام 09:45
  final events = [
    const BellEventInput(id: 1, type: BellEventType.dayStart, minuteOfDay: 480),
    const BellEventInput(
        id: 2,
        type: BellEventType.lessonStart,
        minuteOfDay: 480,
        subject: 'الرياضيات'),
    const BellEventInput(id: 3, type: BellEventType.lessonEnd, minuteOfDay: 525),
    const BellEventInput(id: 4, type: BellEventType.breakStart, minuteOfDay: 525),
    const BellEventInput(id: 5, type: BellEventType.breakEnd, minuteOfDay: 540),
    const BellEventInput(id: 6, type: BellEventType.lessonStart, minuteOfDay: 540),
    const BellEventInput(id: 7, type: BellEventType.lessonEnd, minuteOfDay: 585),
    const BellEventInput(id: 8, type: BellEventType.dayEnd, minuteOfDay: 585),
  ];

  final day = DayScheduleResult(
    date: date,
    status: DayStatus.working,
    segments: SegmentBuilder.build(date, events),
  );

  group('SegmentBuilder', () {
    test('يبني حصتين واستراحة بترقيم صحيح', () {
      expect(day.segments.length, 3);
      expect(day.segments[0].kind, SegmentKind.lesson);
      expect(day.segments[0].number, 1);
      expect(day.segments[0].subject, 'الرياضيات');
      expect(day.segments[1].kind, SegmentKind.breakTime);
      expect(day.segments[2].number, 2);
      expect(day.segments[0].endEventId, 3);
    });
  });

  group('ProgressCalculator', () {
    test('0% عند بداية الحصة', () {
      final s = ProgressCalculator.compute(now: at(8, 0), day: day);
      expect(s.phase, ProgressPhase.inSegment);
      expect(s.percent, 0);
    });

    test('50% في منتصف حصة مدتها 40 دقيقة', () {
      final d = DayScheduleResult(
        date: date,
        status: DayStatus.working,
        segments: [
          DaySegment(
              kind: SegmentKind.lesson,
              name: 'الحصة 1',
              number: 1,
              start: at(8, 0),
              end: at(8, 40)),
        ],
      );
      final s = ProgressCalculator.compute(now: at(8, 20), day: d);
      expect(s.percent, 50);
      expect(s.elapsed, const Duration(minutes: 20));
      expect(s.remaining, const Duration(minutes: 20));
    });

    test('النسبة تعتمد على الوقت الحقيقي لا على عدد التحديثات', () {
      final a = ProgressCalculator.compute(now: at(8, 9), day: day);
      final b = ProgressCalculator.compute(now: at(8, 9), day: day);
      expect(a.fraction, b.fraction);
      expect(a.percent, 20); // 9 / 45 = 20%
    });

    test('لا تصل إلى 100% قبل النهاية فعلًا', () {
      final s = ProgressCalculator.compute(now: at(8, 44, 59), day: day);
      expect(s.phase, ProgressPhase.inSegment);
      expect(s.percent, 99);
    });

    test('عند وقت النهاية تبدأ الاستراحة بدل الحصة', () {
      final s = ProgressCalculator.compute(now: at(8, 45), day: day);
      expect(s.current!.kind, SegmentKind.breakTime);
      expect(s.percent, 0);
    });

    test('اللون البرتقالي (nearEnd) في آخر 5 دقائق', () {
      expect(ProgressCalculator.compute(now: at(8, 30), day: day).nearEnd, false);
      expect(ProgressCalculator.compute(now: at(8, 41), day: day).nearEnd, true);
    });

    test('قبل الدوام وبعده', () {
      final before = ProgressCalculator.compute(now: at(7, 0), day: day);
      expect(before.phase, ProgressPhase.beforeDay);
      expect(before.next!.number, 1);

      final after = ProgressCalculator.compute(now: at(12, 0), day: day);
      expect(after.phase, ProgressPhase.afterDay);
    });

    test('تجاوز النهاية دون تنفيذ الجرس => overdue بنسبة 100%', () {
      final s = ProgressCalculator.compute(
        now: at(9, 47),
        day: day,
        bellExecuted: (_) => false,
      );
      expect(s.phase, ProgressPhase.overdue);
      expect(s.percent, 100);
      expect(s.overrun, const Duration(minutes: 2));
    });

    test('تجاوز النهاية مع تنفيذ الجرس => لا overdue', () {
      final s = ProgressCalculator.compute(
        now: at(9, 47),
        day: day,
        bellExecuted: (_) => true,
      );
      expect(s.phase, ProgressPhase.afterDay);
    });

    test('بعد نافذة التجاوز لا يبقى أحمر', () {
      final s = ProgressCalculator.compute(
        now: at(9, 55),
        day: day,
        bellExecuted: (_) => false,
      );
      expect(s.phase, ProgressPhase.afterDay);
    });

    test('الإجازة وعدم الدوام', () {
      final h = ProgressCalculator.compute(
        now: at(9, 0),
        day: DayScheduleResult(
            date: date, status: DayStatus.holiday, holidayName: 'يوم وطني'),
      );
      expect(h.phase, ProgressPhase.holiday);
      expect(h.holidayName, 'يوم وطني');
      expect(h.current, isNull);

      final n = ProgressCalculator.compute(
        now: at(9, 0),
        day: DayScheduleResult(date: date, status: DayStatus.nonWorkingDay),
      );
      expect(n.phase, ProgressPhase.nonWorkingDay);
    });
  });
}
