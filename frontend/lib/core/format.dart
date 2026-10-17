import 'package:intl/intl.dart';

import 'models/common.dart';
import 'models/vocab.dart';

/// 0.934 → "93%".
String pct(double v) => '${(v * 100).round()}%';

/// 0.934 → "93".
String pctNum(double v) => '${(v * 100).round()}';

/// "88–97%".
String pctRange(double low, double high) => '${pctNum(low)}–${pct(high)}';

/// Percentage points between two shares, rounded.
int points(double a, double b) => ((a - b) * 100).round();

final _day = DateFormat('d MMM y');
final _dayShort = DateFormat('d MMM');
final _month = DateFormat('MMM');

/// "30 Jun 2025".
String day(DateTime d) => _day.format(d);

/// "9 Jun".
String dayShort(DateTime d) => _dayShort.format(d);

/// "Jun".
String month(DateTime d) => _month.format(d);

/// "last 4 weeks" / "last 12 months" / "1 Jan – 31 Mar 2026".
String windowLabel(WindowOut w) => switch (w.window) {
  '28d' => 'last 4 weeks',
  '365d' => 'last 12 months',
  _ => '${dayShort(w.dateFrom)} – ${day(w.dateTo)}',
};

/// "1 patient" / "31 patients".
String patients(int n) => n == 1 ? '1 patient' : '$n patients';

/// The headline figure of an estimate: a percentage, or the range when the sample is small.
String estimateFigure(Estimate e) => e.smallSample ? pctRange(e.low, e.high) : pct(e.value);

/// Where an estimate's weight comes from, in plain words.
String priorPhrase(Estimate e, {String own = "this ward's own data"}) {
  final source = switch (e.priorLevel) {
    PriorLevel.ward => 'this ward over 12 months',
    PriorLevel.wardType => 'similar wards',
    PriorLevel.hospital => 'whole-hospital data',
  };
  if (e.priorWeight < 0.34) return 'Leans mostly on $own';
  if (e.priorWeight < 0.67) return 'Mixes $own with $source';
  return 'Leans mostly on $source (${pct(e.priorWeight)})';
}
