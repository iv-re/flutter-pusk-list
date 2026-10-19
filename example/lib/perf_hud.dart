import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Aggregates [FrameTiming]s reported by the engine (real numbers in
/// profile/release builds).
///
/// Durations go into 0.1ms histograms, so recording a frame and reading a
/// percentile are cheap and don't distort what is being measured. Listeners
/// are notified at most every 250ms.
class FrameStats extends ChangeNotifier {
  FrameStats() {
    SchedulerBinding.instance.addTimingsCallback(_add);
  }

  static const _bucketMicros = 100;
  static const _bucketCount = 1000; // up to 100ms, the rest go to the last.

  final _build = Int32List(_bucketCount);
  final _raster = Int32List(_bucketCount);
  var _count = 0;
  var _jankCount = 0;

  /// Frame budget used to count janky frames.
  double budgetMs = 1000 / 60;
  Timer? _notifyTimer;

  void _add(List<FrameTiming> timings) {
    final budget = budgetMs * 1000;
    for (final f in timings) {
      final build = f.buildDuration.inMicroseconds;
      final raster = f.rasterDuration.inMicroseconds;
      _build[_bucket(build)]++;
      _raster[_bucket(raster)]++;
      _count++;
      if (build > budget || raster > budget) _jankCount++;
    }
    _notifyTimer ??= Timer(const Duration(milliseconds: 250), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  static int _bucket(int micros) =>
      min(micros ~/ _bucketMicros, _bucketCount - 1);

  void reset() {
    _build.fillRange(0, _bucketCount, 0);
    _raster.fillRange(0, _bucketCount, 0);
    _count = 0;
    _jankCount = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_add);
    _notifyTimer?.cancel();
    super.dispose();
  }

  int get count => _count;
  int get jankyFrames => _jankCount;

  double _percentile(Int32List histogram, double p) {
    if (_count == 0) return 0;
    final rank = ((_count - 1) * p).round();
    var seen = 0;
    for (var i = 0; i < _bucketCount; i++) {
      seen += histogram[i];
      if (seen > rank) return (i + 0.5) * _bucketMicros / 1000;
    }
    return _bucketCount * _bucketMicros / 1000;
  }

  double buildP50() => _percentile(_build, 0.5);
  double buildP99() => _percentile(_build, 0.99);
  double rasterP99() => _percentile(_raster, 0.99);
}

/// Compact frame stats; tap to reset.
class PerfHud extends StatelessWidget {
  const PerfHud({required this.stats, super.key});

  final FrameStats stats;

  @override
  Widget build(BuildContext context) {
    final refreshRate = View.of(context).display.refreshRate;
    final budget = 1000 / (refreshRate > 0 ? refreshRate : 60);
    stats.budgetMs = budget;
    final scheme = Theme.of(context).colorScheme;
    // Isolated, so that its repaints don't add to the measured frames.
    return RepaintBoundary(
      child: GestureDetector(
        onTap: stats.reset,
        child: Container(
          width: 210,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.inverseSurface.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListenableBuilder(
            listenable: stats,
            builder: (context, _) {
              final p99 = stats.buildP99();
              final style = TextStyle(
                color: scheme.onInverseSurface,
                fontSize: 11.5,
                height: 1.35,
                fontFeatures: const [FontFeature.tabularFigures()],
              );
              final ok = p99 <= budget;
              return Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 9,
                    color: stats.count == 0
                        ? Colors.grey
                        : ok
                        ? Colors.greenAccent
                        : Colors.orangeAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'build p50 ${stats.buildP50().toStringAsFixed(1)} · '
                      'p99 ${p99.toStringAsFixed(1)} ms\n'
                      'raster p99 ${stats.rasterP99().toStringAsFixed(1)} · '
                      'jank ${stats.jankyFrames}/${stats.count}',
                      style: style,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
