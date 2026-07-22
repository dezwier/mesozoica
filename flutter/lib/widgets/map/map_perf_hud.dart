import 'dart:async';
import 'dart:ui' show FramePhase;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../controllers/map_controller.dart' as map_data;
import '../../services/location_service.dart';

/// Admin-only performance HUD for map thermal / battery diagnosis.
///
/// Samples FPS via [SchedulerBinding] frame timings and polls location counters
/// at ~1–2 Hz. Does not drive map rebuilds.
class MapPerfHud extends StatefulWidget {
  const MapPerfHud({
    super.key,
    required this.rotateMap,
    required this.followUser,
    required this.mapActive,
    required this.mapboxReady,
    required this.rotateCardCount,
  });

  final bool rotateMap;
  final bool followUser;
  final bool mapActive;
  final bool mapboxReady;
  final ValueNotifier<int> rotateCardCount;

  @override
  State<MapPerfHud> createState() => _MapPerfHudState();
}

class _MapPerfHudState extends State<MapPerfHud> {
  static const _sampleInterval = Duration(milliseconds: 500);
  static const _jankThresholdMs = 16.7;

  Timer? _timer;

  final List<FrameTiming> _timings = [];
  double _fps = 0;
  double _avgBuildMs = 0;
  double _avgRasterMs = 0;
  int _jankCount = 0;
  bool _expanded = true;

  int _prevGpsCount = 0;
  int _prevHeadingNotify = 0;
  double _gpsHz = 0;
  double _compassHz = 0;

  DateTime _windowStart = DateTime.now();

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    final loc = context.read<LocationService>();
    _prevGpsCount = loc.gpsUpdateCount;
    _prevHeadingNotify = loc.headingNotifyCount;
    _windowStart = DateTime.now();
    _timer = Timer.periodic(_sampleInterval, (_) => _sample());
  }

  @override
  void dispose() {
    _timer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    _timings.addAll(timings);
    // Keep >1s of ProMotion frames so a late sample doesn't truncate.
    const maxKeep = 256;
    if (_timings.length > maxKeep) {
      _timings.removeRange(0, _timings.length - maxKeep);
    }
  }

  void _sample() {
    if (!mounted) return;

    var buildSum = 0.0;
    var rasterSum = 0.0;
    var jank = 0;
    // One Flutter frame can show up more than once in the timings buffer;
    // unique vsyncStart = one display refresh.
    final vsyncStarts = <int>{};
    for (final t in _timings) {
      final buildMs = t.buildDuration.inMicroseconds / 1000.0;
      final rasterMs = t.rasterDuration.inMicroseconds / 1000.0;
      buildSum += buildMs;
      rasterSum += rasterMs;
      if (buildMs + rasterMs > _jankThresholdMs) jank++;
      vsyncStarts.add(t.timestampInMicroseconds(FramePhase.vsyncStart));
    }
    final n = _timings.length;
    final uniqueVsyncs = vsyncStarts.length;

    // Cadence from vsync timestamps (avoids wall-clock jitter and double-counts).
    var fps = 0.0;
    if (uniqueVsyncs >= 2) {
      final sorted = vsyncStarts.toList()..sort();
      final spanUs = sorted.last - sorted.first;
      if (spanUs > 0) {
        fps = (sorted.length - 1) * 1e6 / spanUs;
      }
    }

    final loc = context.read<LocationService>();
    final now = DateTime.now();
    final elapsedSec =
        now.difference(_windowStart).inMilliseconds.clamp(1, 60000) / 1000.0;
    final gpsDelta = loc.gpsUpdateCount - _prevGpsCount;
    final headingDelta = loc.headingNotifyCount - _prevHeadingNotify;
    _prevGpsCount = loc.gpsUpdateCount;
    _prevHeadingNotify = loc.headingNotifyCount;
    _windowStart = now;

    setState(() {
      _fps = fps;
      _avgBuildMs = n > 0 ? buildSum / n : 0;
      _avgRasterMs = n > 0 ? rasterSum / n : 0;
      _jankCount = jank;
      _gpsHz = gpsDelta / elapsedSec;
      _compassHz = headingDelta / elapsedSec;
      _timings.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Poll snapshot — avoid watch so GPS/compass don't rebuild the HUD tree
    // outside the 2 Hz sampler (sampler already setStates).
    final loc = context.read<LocationService>();
    final mapData = context.read<map_data.MapController>();
    final pos = loc.lastPosition;
    final ageMs = loc.gpsFixAge?.inMilliseconds;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _expanded = !_expanded),
      child: Material(
        color: const Color(0xCC1A1A1A),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: DefaultTextStyle(
            style: const TextStyle(
              fontFamily: 'Courier',
              fontFamilyFallback: ['monospace'],
              fontSize: 10,
              height: 1.25,
              color: Color(0xFFE8E8E8),
            ),
            child: ValueListenableBuilder<int>(
              valueListenable: widget.rotateCardCount,
              builder: (context, cardCount, _) {
                final lines = <String>[
                  'FPS ${_fps.toStringAsFixed(0)}  '
                      'b${_avgBuildMs.toStringAsFixed(1)}/'
                      'r${_avgRasterMs.toStringAsFixed(1)}ms  '
                      'jank$_jankCount',
                  'GPS ${_gpsHz.toStringAsFixed(1)}Hz  '
                      '±${pos?.accuracy.toStringAsFixed(0) ?? '—'}m  '
                      'age${ageMs ?? '—'}ms  '
                      '${loc.isGpsStreamActive ? 'on' : 'off'}'
                      '${loc.isHighPrecisionGps ? ' hi' : ' lo'}',
                  'CMP ${_compassHz.toStringAsFixed(0)}Hz  '
                      'hdg${loc.headingDeg.toStringAsFixed(0)}°  '
                      '${loc.isHeadingStreamActive ? 'on' : 'off'}',
                  if (_expanded) ...[
                    'rot${widget.rotateMap ? '1' : '0'} '
                        'fol${widget.followUser ? '1' : '0'} '
                        'map${widget.mapActive ? '1' : '0'} '
                        'mb${widget.mapboxReady ? '1' : '0'} '
                        'fld${loc.isFieldSession ? '1' : '0'}',
                    'sites${mapData.filteredGeoSites.length} '
                        'cards$cardCount',
                  ],
                ];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final line in lines) Text(line),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
