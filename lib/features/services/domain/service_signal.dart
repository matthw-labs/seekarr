/// The one live figure a service contributes to the stack matrix on
/// `/services`.
///
/// Resolved here rather than in the cell because of the Closed Tone Rule: a
/// widget renders a status, it never derives one.
library;

import 'package:flutter/widgets.dart';

import 'package:seekarr/core/models/service_kpi.dart';
import 'package:seekarr/core/status/media_status.dart';

/// A service's headline metric, already reduced to something paintable.
///
/// Exactly one of these per cell. It answers "what is this service doing right
/// now", which is a different question from "is it reachable" — the summary
/// answers that.
@immutable
class ServiceSignal {
  /// The metric named in the matrix's own words, e.g. `missing`, `pending`,
  /// `incoming`. Lower case and already singular or plural to match [value].
  ///
  /// Empty when [value] is itself a state word: SABnzbd's paused queue arrives
  /// as the KPI `Status: Paused`, and the cell paints value-then-label, so
  /// carrying the label would print "Paused status" — a column header for a
  /// table this surface does not have.
  ///
  /// Not uppercased, and no longer set in the eyebrow style: casing is the
  /// cell's typography, and screen readers spell out short all-caps tokens they
  /// do not recognise. See [_matrixLabel] for why these words are not simply
  /// the KPI's own.
  final String label;

  /// Preformatted figure, e.g. `12`, `2.4 MB/s`, `94%`.
  final String value;

  /// Small leading glyph, carried over from the source KPI.
  final IconData icon;

  /// How the figure should read. [StatusTone.neutral] means "nothing is asking
  /// for you" and is the resting state of a healthy stack.
  final StatusTone tone;

  const ServiceSignal({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
  });

  /// Whether this figure is the reason you would look at the cell.
  bool get needsAttention => tone != StatusTone.neutral;

  /// The signal spoken after the service name and its reachability.
  ///
  /// Reads as a sentence rather than as the two visual fragments: the cell
  /// paints `12 missing`, which spoken back in that order is "twelve missing"
  /// only by luck of English word order and becomes nonsense for `2.4 MB/s
  /// incoming`.
  ///
  /// Capitalised because it opens a clause of its own after the reachability
  /// word, and reduced to the bare [value] when there is no label — "Paused"
  /// is already the whole fact.
  String get spoken {
    if (label.isEmpty) return value;
    return '${label[0].toUpperCase()}${label.substring(1)} $value';
  }
}

/// Labels whose flagged state means bytes are moving, not that something is
/// wrong.
///
/// An active download is the system working, so it reads as activity rather than
/// as a warning. Everything else a service flags is something you may need to
/// act on.
const Set<String> _activityLabels = {'Down'};

/// Labels whose flagged state is an outright fault rather than a backlog.
///
/// A failing indexer and an exited stack are both things that were meant to be
/// running and are not — distinct from a queue of work that simply has not
/// happened yet.
const Set<String> _faultLabels = {'Fails', 'Exited'};

/// The matrix's word for a metric, where the KPI's own label is wrong *here*.
///
/// A KPI label is written for the per-service peek, where four of them sit in a
/// row and read as column headings. The matrix uses one of them as a phrase
/// beside its figure, in a grid of up to thirteen cells whose other possible
/// live line is the word "Offline" — and that context breaks three of them:
///
///  * **`Down`** is the download *rate*. Beside `Up` on a peek it cannot be
///    misread; on a reachability instrument `2.4 MB/s down` says the service is
///    down. It is the one word this screen cannot borrow, and the code already
///    knew as much — `_activityLabels` exists to stop it reading as a fault.
///    `incoming` rather than `downloading` because the cell has to fit a rate,
///    an icon and a word into 168pt: measured, `2.4 MB/s downloading` ellipsises
///    to "downloa…" at the *default* reading size, and a truncated word is a
///    worse label than a shorter one.
///  * **`Fails`** is Prowlarr's own truncation, and it is not a noun. The figure
///    counts failed queries.
///  * **`Status`** names a field, not a fact. Its value is already the state
///    word, so the label is dropped entirely rather than printed after it.
///
/// Everything else keeps the service's own vocabulary lower-cased, including
/// terms the audience genuinely knows — Bazarr's `Wanted`, Docker's `Exited`.
/// Plain-languaging those would flatten terminology, not clarify it.
const Map<String, String> _matrixLabelOverrides = {
  'Down': 'incoming',
  'Up': 'outgoing',
  'Fails': 'failures',
  'Status': '',
};

/// Labels that already read the same for one and for many.
const Set<String> _invariantLabels = {'series'};

/// Picks the one KPI worth showing from a service's full KPI list.
///
/// The choice is not a table in this file, and deliberately so. Every KPI
/// builder in `service_kpi_provider.dart` already marks its own noteworthy
/// metric by giving it a non-null [ServiceKpi.accent] — `_warnIf(missing > 0)`,
/// `_warnIf(activeAlerts > 0)`, `_warnIf(exited > 0)`, and so on. That flag is
/// the domain's own judgment about its own data, written next to the code that
/// computes it.
///
/// So: **the first flagged KPI wins, and the first KPI is the fallback.** A
/// service added to the registry gets a correct live line for free, and the
/// judgment stays in one place instead of being restated here and drifting.
///
/// Returns null only when a service reports no KPIs at all, in which case the
/// cell shows its reachability and nothing else.
ServiceSignal? resolveServiceSignal(List<ServiceKpi> kpis) {
  if (kpis.isEmpty) return null;

  final flagged = kpis.where((kpi) => kpi.accent != null).firstOrNull;

  // Nothing is asking for attention, so the headline metric carries the cell:
  // the service's scale, not its problems.
  final source = flagged ?? kpis.first;

  return ServiceSignal(
    label: _matrixLabel(source.label, source.value),
    value: source.value,
    icon: source.icon,
    // The tone reads the *KPI's* label, not the rewritten one: the vocabulary
    // above is presentation, and keying the closed tone set off it would mean a
    // renamed word silently changed a service's health colour.
    tone: flagged == null ? StatusTone.neutral : _toneFor(flagged.label),
  );
}

/// A KPI label as the matrix says it: rewritten where needed, lower case, and
/// agreeing in number with its own figure.
///
/// The plural rule is deliberately mechanical — drop a trailing `s` when the
/// figure parses as exactly 1 — because it has to hold for every service in the
/// registry, including ones added later. `1 alerts` and `1 stacks` were both
/// live before it. A figure that is not a bare integer (`2.4 MB/s`, `85%`,
/// `4/6`, `Paused`) parses to null and is left alone, which is correct: those
/// labels are not counts.
String _matrixLabel(String kpiLabel, String value) {
  final label = _matrixLabelOverrides[kpiLabel] ?? kpiLabel.toLowerCase();
  if (label.isEmpty) return '';
  if (int.tryParse(value) != 1) return label;
  if (_invariantLabels.contains(label) || !label.endsWith('s')) return label;
  return label.substring(0, label.length - 1);
}

StatusTone _toneFor(String label) {
  if (_activityLabels.contains(label)) return StatusTone.info;
  if (_faultLabels.contains(label)) return StatusTone.error;
  return StatusTone.warning;
}
