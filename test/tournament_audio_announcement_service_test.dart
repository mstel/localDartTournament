import 'dart:async';

import 'package:dart_tournament_manager/features/tournaments/application/tournament_audio_announcement_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAudioOutput implements TournamentAnnouncementAudioOutput {
  final List<String> events = [];
  bool failCue = false;
  bool failSpeech = false;

  @override
  Future<void> playCue() async {
    events.add('cue');
    if (failCue) throw StateError('audio unavailable');
  }

  @override
  Future<void> speakGerman(String text) async {
    events.add('speak:$text');
    if (failSpeech) throw StateError('tts unavailable');
  }

  @override
  Future<void> stopSpeaking() async {
    events.add('stop');
  }

  @override
  Future<void> dispose() async {
    events.add('dispose');
  }
}

void main() {
  test(
    'plays the cue, waits one second, then speaks the recommendation',
    () async {
      final output = _FakeAudioOutput();
      final events = output.events;
      final service = TournamentAudioAnnouncementService(
        output: output,
        delay: (duration) async {
          expect(duration, const Duration(seconds: 1));
          events.add('delay');
        },
      );

      await service.announce(
        text: 'Nächste Partie: Marvin gegen Daniel an Board 3.',
        isStillCurrent: () => true,
      );

      expect(events, [
        'stop',
        'cue',
        'delay',
        'speak:Nächste Partie: Marvin gegen Daniel an Board 3.',
      ]);
    },
  );

  test('does not speak a recommendation that is no longer current', () async {
    final output = _FakeAudioOutput();
    final service = TournamentAudioAnnouncementService(
      output: output,
      delay: (_) async {},
    );

    await service.announce(
      text: 'Veraltete Partie',
      isStillCurrent: () => false,
    );

    expect(output.events, ['stop', 'cue']);
  });

  test('speaks the alternative after a separate half-second pause', () async {
    final output = _FakeAudioOutput();
    final service = TournamentAudioAnnouncementService(
      output: output,
      delay: (duration) async {
        output.events.add('delay:${duration.inMilliseconds}');
      },
    );

    await service.announce(
      text: 'Nächste Partie: Marvin gegen Daniel an Board Nummer 3.',
      alternativeText: 'Alternativ: Silas gegen Patrick an Board Nummer 3.',
      isStillCurrent: () => true,
    );

    expect(output.events, [
      'stop',
      'cue',
      'delay:1000',
      'speak:Nächste Partie: Marvin gegen Daniel an Board Nummer 3.',
      'delay:500',
      'speak:Alternativ: Silas gegen Patrick an Board Nummer 3.',
    ]);
  });

  test(
    'skips an alternative that is no longer current after the pause',
    () async {
      final output = _FakeAudioOutput();
      var validityChecks = 0;
      final service = TournamentAudioAnnouncementService(
        output: output,
        delay: (_) async {},
      );

      await service.announce(
        text: 'Nächste Partie',
        alternativeText: 'Veraltete Alternative',
        isStillCurrent: () => ++validityChecks < 3,
      );

      expect(output.events, ['stop', 'cue', 'speak:Nächste Partie']);
    },
  );

  test('cancellation while waiting prevents stale speech', () async {
    final output = _FakeAudioOutput();
    final delayCompleter = Completer<void>();
    final service = TournamentAudioAnnouncementService(
      output: output,
      delay: (_) => delayCompleter.future,
    );
    final announcement = service.announce(
      text: 'Veraltete Partie',
      isStillCurrent: () => true,
    );

    await Future<void>.delayed(Duration.zero);
    service.cancel();
    delayCompleter.complete();
    await announcement;

    expect(output.events, ['stop', 'cue', 'stop']);
  });

  test('audio output failures do not throw or prevent later steps', () async {
    final output = _FakeAudioOutput()
      ..failCue = true
      ..failSpeech = true;
    final service = TournamentAudioAnnouncementService(
      output: output,
      delay: (_) async {},
    );

    await expectLater(
      service.announce(text: 'Empfehlung', isStillCurrent: () => true),
      completes,
    );
    expect(output.events, ['stop', 'cue', 'speak:Empfehlung']);
  });
}
