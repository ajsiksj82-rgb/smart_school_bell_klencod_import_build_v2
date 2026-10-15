/// نماذج ميزة متابعة الحصة الحالية، ومُحوِّل أحداث الجرس إلى فترات زمنية.

enum BellEventType {
  dayStart,
  assemblyStart,
  lessonStart,
  lessonEnd,
  breakStart,
  breakEnd,
  dayEnd,
}

enum SegmentKind { assembly, lesson, breakTime }

enum DayStatus { working, holiday, nonWorkingDay, noSchedule }

/// حدث جرس كما يأتي من جدول bell_events (قبل التحويل إلى فترات).
class BellEventInput {
  const BellEventInput({
    required this.id,
    required this.type,
    required this.minuteOfDay,
    this.label,
    this.subject,
    this.enabled = true,
  });

  final int id;
  final BellEventType type;

  /// الدقيقة منذ منتصف الليل (مثال: 08:45 => 525).
  final int minuteOfDay;
  final String? label;
  final String? subject;
  final bool enabled;
}

/// فترة زمنية فعلية (حصة / استراحة / طابور) بتاريخ ووقت محليين كاملين.
class DaySegment {
  const DaySegment({
    required this.kind,
    required this.name,
    required this.start,
    required this.end,
    this.number,
    this.subject,
    this.endEventId,
    this.endBellEnabled = true,
  });

  final SegmentKind kind;
  final String name;
  final int? number;
  final String? subject;
  final DateTime start;
  final DateTime end;

  /// معرّف حدث الجرس الذي ينهي هذه الفترة (للتحقق من تنفيذه في السجل).
  final int? endEventId;

  /// إذا كان جرس النهاية معطّلًا فلا يُعرض اللون الأحمر عند تجاوز الوقت.
  final bool endBellEnabled;

  Duration get total => end.difference(start);
}

class DayScheduleResult {
  const DayScheduleResult({
    required this.date,
    required this.status,
    this.segments = const [],
    this.holidayName,
  });

  final DateTime date;
  final DayStatus status;
  final List<DaySegment> segments;
  final String? holidayName;
}

class SegmentBuilder {
  /// يحوّل أحداث يوم واحد إلى فترات مرتبة.
  /// - بداية الحصة/الاستراحة/الطابور تفتح فترة.
  /// - نهاية الحصة/الاستراحة/الدوام أو بداية فترة جديدة تغلق الفترة المفتوحة.
  /// الأحداث المعطّلة تبقى حدودًا للفترات، لكن جرسها لا يُنتظر.
  static List<DaySegment> build(DateTime date, List<BellEventInput> events) {
    final sorted = [...events]
      ..sort((a, b) => a.minuteOfDay.compareTo(b.minuteOfDay));

    DateTime at(int m) =>
        DateTime(date.year, date.month, date.day, m ~/ 60, m % 60);

    final out = <DaySegment>[];
    BellEventInput? open;
    int? openNumber;
    var lessonCount = 0;

    void close(BellEventInput end) {
      final o = open;
      if (o == null) return;
      final s = at(o.minuteOfDay);
      final e = at(end.minuteOfDay);
      if (e.isAfter(s)) {
        final label = o.label?.trim();
        final hasLabel = label != null && label.isNotEmpty;
        switch (o.type) {
          case BellEventType.lessonStart:
            out.add(DaySegment(
              kind: SegmentKind.lesson,
              name: hasLabel ? label : 'الحصة $openNumber',
              number: openNumber,
              subject: o.subject,
              start: s,
              end: e,
              endEventId: end.id,
              endBellEnabled: end.enabled,
            ));
          case BellEventType.breakStart:
            out.add(DaySegment(
              kind: SegmentKind.breakTime,
              name: hasLabel ? label : 'الاستراحة',
              start: s,
              end: e,
              endEventId: end.id,
              endBellEnabled: end.enabled,
            ));
          case BellEventType.assemblyStart:
            out.add(DaySegment(
              kind: SegmentKind.assembly,
              name: hasLabel ? label : 'الطابور الصباحي',
              start: s,
              end: e,
              endEventId: end.id,
              endBellEnabled: end.enabled,
            ));
          default:
            break;
        }
      }
      open = null;
      openNumber = null;
    }

    for (final ev in sorted) {
      switch (ev.type) {
        case BellEventType.lessonStart:
          close(ev);
          open = ev;
          openNumber = ++lessonCount;
        case BellEventType.breakStart:
        case BellEventType.assemblyStart:
          close(ev);
          open = ev;
        case BellEventType.lessonEnd:
        case BellEventType.breakEnd:
        case BellEventType.dayEnd:
          close(ev);
        case BellEventType.dayStart:
          break;
      }
    }
    return out;
  }
}
