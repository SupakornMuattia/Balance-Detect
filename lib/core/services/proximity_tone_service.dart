import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:balance_detect/core/logging/app_logger.dart';
import 'package:flutter/services.dart';

class ToneNote {
  const ToneNote({
    required this.frequencyHz,
    required this.duration,
    required this.volume,
  });

  final double frequencyHz;
  final Duration duration;

  /// 0.0 (silent) to 1.0 (full scale).
  final double volume;

  Map<String, Object> toMap() => <String, Object>{
    'frequencyHz': frequencyHz,
    'durationMs': duration.inMilliseconds,
    'volume': volume,
  };
}

abstract interface class TonePlatform {
  Future<void> play(List<ToneNote> notes);
  Future<void> stop();
}

/// Native Android sine-wave synthesizer (see `TonePlayer.kt`).
class MethodChannelTonePlatform implements TonePlatform {
  static const _channel = MethodChannel('com.balancedetect/tone');

  @override
  Future<void> play(List<ToneNote> notes) =>
      _channel.invokeMethod<void>('playSequence', <String, Object>{
        'notes': [for (final note in notes) note.toMap()],
      });

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');
}

/// How a single guidance beep sounds at a given fingertip-to-target distance.
///
/// Far from the target the beep is loud, high and rapid so it is easy to hear
/// while the participant faces away from the screen. As the fingertip closes
/// in, the beep becomes quieter, lower and slower, ending in a gentle pulse
/// just before contact.
class ProximityTone {
  const ProximityTone({
    required this.proximity,
    required this.frequencyHz,
    required this.volume,
    required this.beepDuration,
    required this.interval,
  });

  factory ProximityTone.forDistance({
    required double distanceCm,
    required double referenceDistanceCm,
  }) {
    final reference = referenceDistanceCm <= 0 ? 1.0 : referenceDistanceCm;
    final proximity = (1 - distanceCm / reference).clamp(0.0, 1.0);
    // Ease-out so the change is noticeable as soon as the reach begins.
    final eased = 1 - (1 - proximity) * (1 - proximity);
    return ProximityTone(
      proximity: proximity,
      frequencyHz: lerpDouble(farFrequencyHz, nearFrequencyHz, eased)!,
      volume: lerpDouble(farVolume, nearVolume, eased)!,
      beepDuration: Duration(
        milliseconds: lerpDouble(farBeepMs, nearBeepMs, eased)!.round(),
      ),
      interval: Duration(
        milliseconds: lerpDouble(farIntervalMs, nearIntervalMs, eased)!.round(),
      ),
    );
  }

  static const farFrequencyHz = 880.0;
  static const nearFrequencyHz = 440.0;
  static const farVolume = 1.0;
  static const nearVolume = 0.22;
  static const farBeepMs = 80.0;
  static const nearBeepMs = 240.0;
  static const farIntervalMs = 220.0;
  static const nearIntervalMs = 900.0;

  /// 0.0 at (or beyond) the starting distance, 1.0 at the target.
  final double proximity;
  final double frequencyHz;
  final double volume;
  final Duration beepDuration;

  /// Time from the start of one beep to the start of the next.
  final Duration interval;

  ToneNote get note => ToneNote(
    frequencyHz: frequencyHz,
    duration: beepDuration,
    volume: volume,
  );
}

/// Plays a repeating proximity beep that follows the latest distance update,
/// and a short ascending chime when the target is touched.
///
/// Distance updates arrive with every pose frame; the beep loop reads the most
/// recent value at each beep, so tempo and loudness track the hand smoothly.
/// If updates stop (fingertip lost), the beeps pause instead of repeating a
/// stale distance, and resume with the next update.
class ProximityToneService {
  ProximityToneService({
    TonePlatform? platform,
    DateTime Function()? now,
    this.staleAfter = const Duration(milliseconds: 700),
  }) : _platform = platform ?? MethodChannelTonePlatform(),
       _now = now ?? DateTime.now;

  static const completionChime = <ToneNote>[
    ToneNote(
      frequencyHz: 523.25,
      duration: Duration(milliseconds: 110),
      volume: .8,
    ),
    ToneNote(
      frequencyHz: 659.25,
      duration: Duration(milliseconds: 110),
      volume: .8,
    ),
    ToneNote(
      frequencyHz: 783.99,
      duration: Duration(milliseconds: 110),
      volume: .8,
    ),
    ToneNote(
      frequencyHz: 1046.50,
      duration: Duration(milliseconds: 420),
      volume: .85,
    ),
  ];

  static Duration get completionChimeDuration => completionChime.fold(
    Duration.zero,
    (total, note) => total + note.duration,
  );

  final TonePlatform _platform;
  final DateTime Function() _now;
  final Duration staleAfter;

  ProximityTone? _current;
  DateTime? _lastUpdateAt;
  Timer? _timer;
  bool _active = false;
  bool _enabled = true;
  bool _available = true;
  bool _disposed = false;

  bool get enabled => _enabled;
  bool get isActive => _active;
  bool get isBeeping => _timer != null;
  ProximityTone? get currentTone => _current;

  /// Starts accepting distance updates; beeps begin with the first update.
  void start() {
    if (_disposed) return;
    _active = true;
    _current = null;
    _lastUpdateAt = null;
    AppLogger.event('proximity_tone_started', <String, Object?>{
      'enabled': _enabled,
      'available': _available,
    });
  }

  void updateDistance({
    required double distanceCm,
    required double referenceDistanceCm,
  }) {
    if (_disposed || !_active) return;
    _current = ProximityTone.forDistance(
      distanceCm: distanceCm,
      referenceDistanceCm: referenceDistanceCm,
    );
    _lastUpdateAt = _now();
    if (_timer == null) _beep();
  }

  /// Stops the proximity loop and plays the "target touched" chime.
  Future<void> playComplete() async {
    if (_disposed) return;
    _haltLoop();
    if (!_enabled) return;
    AppLogger.event('fullerton_target_tone_complete');
    await _send(() => _platform.play(completionChime));
  }

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    if (!enabled) {
      _timer?.cancel();
      _timer = null;
      await _send(_platform.stop);
    }
  }

  Future<void> stop() async {
    if (_disposed) return;
    _haltLoop();
    await _send(_platform.stop);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _haltLoop();
    await _send(_platform.stop);
    _disposed = true;
  }

  void _haltLoop() {
    _active = false;
    _timer?.cancel();
    _timer = null;
    _current = null;
  }

  void _beep() {
    _timer = null;
    final tone = _current;
    final updatedAt = _lastUpdateAt;
    if (_disposed || !_active || !_enabled || tone == null) return;
    if (updatedAt == null || _now().difference(updatedAt) > staleAfter) return;
    unawaited(_send(() => _platform.play(<ToneNote>[tone.note])));
    _timer = Timer(tone.interval, _beep);
  }

  Future<void> _send(Future<void> Function() operation) async {
    if (!_available) return;
    try {
      await operation();
    } on MissingPluginException {
      // Non-Android platforms (and unit tests) have no native tone player.
      // On Android this means the app was hot-reloaded instead of rebuilt
      // after the native TonePlayer was added.
      _available = false;
      AppLogger.event('proximity_tone_unavailable');
    } catch (error) {
      AppLogger.error('proximity_tone_failed', error);
    }
  }
}
