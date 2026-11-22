import 'package:balance_detect/core/services/proximity_tone_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProximityTone', () {
    test('is loud, high and rapid at the starting distance', () {
      final tone = ProximityTone.forDistance(
        distanceCm: 25,
        referenceDistanceCm: 25,
      );
      expect(tone.proximity, 0);
      expect(tone.volume, ProximityTone.farVolume);
      expect(tone.frequencyHz, ProximityTone.farFrequencyHz);
      expect(tone.interval.inMilliseconds, ProximityTone.farIntervalMs);
    });

    test('is quiet, low and slow at the target', () {
      final tone = ProximityTone.forDistance(
        distanceCm: 0,
        referenceDistanceCm: 25,
      );
      expect(tone.proximity, 1);
      expect(tone.volume, closeTo(ProximityTone.nearVolume, 1e-9));
      expect(tone.frequencyHz, ProximityTone.nearFrequencyHz);
      expect(tone.interval.inMilliseconds, ProximityTone.nearIntervalMs);
    });

    test('gets steadily gentler as the fingertip approaches', () {
      ProximityTone at(double cm) =>
          ProximityTone.forDistance(distanceCm: cm, referenceDistanceCm: 25);
      final far = at(20);
      final mid = at(12);
      final near = at(4);
      expect(far.volume, greaterThan(mid.volume));
      expect(mid.volume, greaterThan(near.volume));
      expect(far.interval, lessThan(mid.interval));
      expect(mid.interval, lessThan(near.interval));
      expect(far.frequencyHz, greaterThan(near.frequencyHz));
    });

    test('clamps distances beyond the start and guards a zero reference', () {
      expect(
        ProximityTone.forDistance(
          distanceCm: 60,
          referenceDistanceCm: 25,
        ).proximity,
        0,
      );
      expect(
        ProximityTone.forDistance(
          distanceCm: 0,
          referenceDistanceCm: 0,
        ).proximity,
        1,
      );
    });
  });

  group('ProximityToneService', () {
    test('beeps only after start and follows the latest distance', () {
      fakeAsync((async) {
        final platform = _FakeTonePlatform();
        final service = ProximityToneService(
          platform: platform,
          now: () => DateTime(2026).add(async.elapsed),
        );

        service.updateDistance(distanceCm: 20, referenceDistanceCm: 20);
        async.flushMicrotasks();
        expect(platform.played, isEmpty);

        service.start();
        service.updateDistance(distanceCm: 20, referenceDistanceCm: 20);
        async.flushMicrotasks();
        expect(platform.played, hasLength(1));
        expect(platform.played.single.single.volume, ProximityTone.farVolume);

        // Further updates before the next beep do not trigger extra beeps.
        service.updateDistance(distanceCm: 2, referenceDistanceCm: 20);
        async.flushMicrotasks();
        expect(platform.played, hasLength(1));

        async.elapse(const Duration(milliseconds: 220));
        expect(platform.played, hasLength(2));
        expect(
          platform.played.last.single.volume,
          lessThan(ProximityTone.farVolume),
        );
      });
    });

    test('pauses when distance updates stop and resumes on update', () {
      fakeAsync((async) {
        final platform = _FakeTonePlatform();
        final service = ProximityToneService(
          platform: platform,
          now: () => DateTime(2026).add(async.elapsed),
        )..start();

        service.updateDistance(distanceCm: 20, referenceDistanceCm: 20);
        async.elapse(const Duration(seconds: 3));
        final countWhileLost = platform.played.length;
        expect(countWhileLost, lessThanOrEqualTo(5));
        expect(service.isBeeping, isFalse);

        async.elapse(const Duration(seconds: 2));
        expect(platform.played, hasLength(countWhileLost));

        service.updateDistance(distanceCm: 10, referenceDistanceCm: 20);
        async.flushMicrotasks();
        expect(platform.played, hasLength(countWhileLost + 1));
      });
    });

    test('touching the target stops beeps and plays the completion chime', () {
      fakeAsync((async) {
        final platform = _FakeTonePlatform();
        final service = ProximityToneService(
          platform: platform,
          now: () => DateTime(2026).add(async.elapsed),
        )..start();
        service.updateDistance(distanceCm: 1, referenceDistanceCm: 20);
        async.flushMicrotasks();

        service.playComplete();
        async.flushMicrotasks();
        expect(platform.played.last, ProximityToneService.completionChime);
        final count = platform.played.length;

        service.updateDistance(distanceCm: 1, referenceDistanceCm: 20);
        async.elapse(const Duration(seconds: 2));
        expect(platform.played, hasLength(count));
      });
    });

    test('muting silences beeps and the completion chime', () {
      fakeAsync((async) {
        final platform = _FakeTonePlatform();
        final service = ProximityToneService(
          platform: platform,
          now: () => DateTime(2026).add(async.elapsed),
        )..start();
        service.setEnabled(false);
        service.updateDistance(distanceCm: 10, referenceDistanceCm: 20);
        service.playComplete();
        async.elapse(const Duration(seconds: 1));
        expect(platform.played, isEmpty);
        expect(platform.stopCount, greaterThan(0));
      });
    });
  });
}

class _FakeTonePlatform implements TonePlatform {
  final List<List<ToneNote>> played = <List<ToneNote>>[];
  int stopCount = 0;

  @override
  Future<void> play(List<ToneNote> notes) async => played.add(notes);

  @override
  Future<void> stop() async => stopCount += 1;
}
