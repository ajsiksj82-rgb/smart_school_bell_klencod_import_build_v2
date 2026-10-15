import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../models/lesson_progress_models.dart';
import '../services/lesson_progress_controller.dart';
import '../services/progress_calculator.dart';

const Color _blue = Color(0xFF1565C0);
const Color _green = Color(0xFF2E7D32);
const Color _orange = Color(0xFFEF6C00);
const Color _red = Color(0xFFC62828);

/// بطاقة متابعة الحصة الحالية للشاشة الرئيسية.
class LessonProgressCard extends StatelessWidget {
  const LessonProgressCard({super.key, required this.controller});

  final LessonProgressController controller;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ValueListenableBuilder<ProgressSnapshot?>(
            valueListenable: controller.snapshot,
            builder: (context, s, _) {
              if (s == null) {
                return controller.lastError != null
                    ? const _Message(
                        icon: Icons.error_outline,
                        text: 'تعذّر تحميل جدول الحصص')
                    : const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      );
              }
              return s.current != null ? _ActiveView(s) : _IdleView(s);
            },
          ),
        ),
      ),
    );
  }
}

class _ActiveView extends StatelessWidget {
  const _ActiveView(this.s);

  final ProgressSnapshot s;

  Color get _color {
    if (s.phase == ProgressPhase.overdue) return _red;
    if (s.nearEnd) return _orange;
    return s.current!.kind == SegmentKind.lesson ? _blue : _green;
  }

  @override
  Widget build(BuildContext context) {
    final seg = s.current!;
    final color = _color;
    final overdue = s.phase == ProgressPhase.overdue;
    final theme = Theme.of(context);

    return Semantics(
      label: '${seg.name}، التقدم ${s.percent} بالمئة',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _KindChip(kind: seg.kind, color: color),
                const Spacer(),
                Text(
                  '${_hm(seg.start)} – ${_hm(seg.end)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              seg.name,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (seg.kind == SegmentKind.lesson)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 8,
                  children: [
                    if (seg.number != null)
                      _SmallTag('رقم الحصة: ${seg.number}'),
                    if (seg.subject != null && seg.subject!.trim().isNotEmpty)
                      _SmallTag('المادة: ${seg.subject!.trim()}'),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${s.percent}%',
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      overdue ? 'تجاوز وقت النهاية بـ' : 'العد التنازلي لجرس النهاية',
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      overdue ? '+${_clock(s.overrun)}' : _clock(s.remaining),
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: color,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LinearProgressIndicator(
                value: s.fraction,
                minHeight: 18,
                backgroundColor: color.withAlpha(38),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Stat('المنقضي', _words(s.elapsed, up: false)),
                _Stat('المتبقي', overdue ? 'انتهى' : _words(s.remaining, up: true)),
                _Stat('المدة الكلية', _words(seg.total, up: false)),
              ],
            ),
            if (overdue)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'حان وقت النهاية ولم يُسجَّل تنفيذ الجرس. يمكنك تشغيله يدويًا.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _IdleView extends StatelessWidget {
  const _IdleView(this.s);

  final ProgressSnapshot s;

  @override
  Widget build(BuildContext context) {
    final (icon, title) = switch (s.phase) {
      ProgressPhase.holiday => (
          Icons.beach_access,
          s.holidayName != null && s.holidayName!.trim().isNotEmpty
              ? 'اليوم إجازة: ${s.holidayName}'
              : 'اليوم إجازة'
        ),
      ProgressPhase.nonWorkingDay => (Icons.event_busy, 'لا يوجد دوام اليوم'),
      ProgressPhase.noSchedule => (
          Icons.calendar_today_outlined,
          'لا يوجد جدول حصص لهذا اليوم'
        ),
      ProgressPhase.beforeDay => (Icons.schedule, 'لم يبدأ الدوام بعد'),
      ProgressPhase.afterDay => (Icons.check_circle_outline, 'انتهى الدوام اليوم'),
      _ => (Icons.pause_circle_outline, 'لا توجد حصة حالية'),
    };

    final n = s.next;
    String? nextLine;
    if (n != null) {
      final label = n.kind == SegmentKind.lesson ? n.name : 'القادم: ${n.name}';
      final prefix = n.kind == SegmentKind.lesson ? 'الحصة القادمة: ' : '';
      nextLine = '$prefix$label — ${_dayWord(s.now, n.start)} ${_hm(n.start)}';
      if (s.phase == ProgressPhase.gap || s.phase == ProgressPhase.beforeDay) {
        nextLine += '\nتبدأ بعد ${_words(n.start.difference(s.now), up: true)}';
      }
    }

    return _Message(icon: icon, text: title, sub: nextLine);
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.sub});

  final IconData icon;
  final String text;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 36, color: Colors.blueGrey),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              if (sub != null) ...[
                const SizedBox(height: 4),
                Text(sub!, style: theme.textTheme.bodyMedium),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.kind, required this.color});

  final SegmentKind kind;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final label = switch (kind) {
      SegmentKind.lesson => 'حصة جارية',
      SegmentKind.breakTime => 'استراحة',
      SegmentKind.assembly => 'الطابور',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

class _SmallTag extends StatelessWidget {
  const _SmallTag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Chip(
        label: Text(text),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(value,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ───────── تنسيق الوقت ─────────

String _two(int v) => v.toString().padLeft(2, '0');

String _hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// عدّاد: mm:ss أو h:mm:ss. يُقرَّب للأعلى كي لا يظهر 00:00 قبل الجرس فعلًا.
String _clock(Duration d) {
  final total = ((d.inMilliseconds + 999) ~/ 1000).clamp(0, 1 << 30);
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  return h > 0 ? '$h:${_two(m)}:${_two(s)}' : '${_two(m)}:${_two(s)}';
}

/// نص مختصر: "1 س 05 د" أو "27 د 05 ث" أو "45 ث".
/// up=true تقريب للأعلى (للمتبقي)، وإلا للأسفل (للمنقضي).
String _words(Duration d, {required bool up}) {
  final ms = d.inMilliseconds < 0 ? 0 : d.inMilliseconds;
  final total = up ? (ms + 999) ~/ 1000 : ms ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) return '$h س ${_two(m)} د';
  if (m > 0) return '$m د ${_two(s)} ث';
  return '$s ث';
}

const _weekdays = {
  DateTime.saturday: 'السبت',
  DateTime.sunday: 'الأحد',
  DateTime.monday: 'الاثنين',
  DateTime.tuesday: 'الثلاثاء',
  DateTime.wednesday: 'الأربعاء',
  DateTime.thursday: 'الخميس',
  DateTime.friday: 'الجمعة',
};

String _dayWord(DateTime now, DateTime t) {
  final a = DateTime(now.year, now.month, now.day);
  final b = DateTime(t.year, t.month, t.day);
  final diff = b.difference(a).inDays;
  if (diff == 0) return 'اليوم';
  if (diff == 1) return 'غدًا';
  return _weekdays[t.weekday] ?? '';
}
