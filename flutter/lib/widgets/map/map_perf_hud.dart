import 'dart:async';

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
    const maxKeep = 120;
    if (_timings.length > maxKeep) {
      _timings.removeRange(0, _timings.length - maxKeep);
    }
  }

  void _sample() {
    if (!mounted) return;

    var buildSum = 0.0;
    var rasterSum = 0.0;
    var jank = 0;
    for (final t in _timings) {
      final buildMs = t.buildDuration.inMicroseconds / 1000.0;
      final rasterMs = t.rasterDuration.inMicroseconds / 1000.0;
      buildSum += buildMs;
      rasterSum += rasterMs;
      // Frame missed its budget if build+raster alone exceeded ~16.7ms.
      if (buildMs + rasterMs > _jankThresholdMs) jank++;
    }
    final n = _timings.length;

    final loc = context.read<LocationService>();
    final now = DateTime.now();
    final elapsedSec =
        now.difference(_windowStart).inMilliseconds.clamp(1, 60000) / 1000.0;
    // Wall-clock FPS: frames Flutter reported in this sample window.
    // (Do not use sum(totalSpan) — that is busy-time and invents 300–400+ "FPS".)
    final fps = n / elapsedSec;
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
