import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

abstract interface class TournamentAnnouncementAudioOutput {
  Future<void> playCue();
  Future<void> speakGerman(String text);
  Future<void> stopSpeaking();
  Future<void> dispose();
}

class TournamentAudioAnnouncementService {
  TournamentAudioAnnouncementService({
    TournamentAnnouncementAudioOutput? output,
    Future<void> Function(Duration)? delay,
  }) : _output = output ?? _LocalTournamentAnnouncementAudioOutput(),
       _delay = delay ?? Future<void>.delayed;

  final TournamentAnnouncementAudioOutput _output;
  final Future<void> Function(Duration) _delay;
  int _requestId = 0;

  Future<void> announce({
    required String text,
    String? alternativeText,
    List<String>? alternativeTexts,
    required bool Function() isStillCurrent,
  }) async {
    final requestId = ++_requestId;
    final allAlternatives = [
      ...(alternativeText == null ? const <String>[] : [alternativeText]),
      ...(alternativeTexts ?? const <String>[]),
    ];
    await _runAudioOperation(
      'Vorherige Sprachausgabe stoppen',
      _output.stopSpeaking,
    );
    await _runAudioOperation('Signalton abspielen', _output.playCue);
    try {
      await _delay(const Duration(seconds: 1));
    } catch (error) {
      debugPrint('Wartezeit vor Turnieransage fehlgeschlagen: $error');
      return;
    }

    if (requestId != _requestId) return;
    try {
      if (!isStillCurrent()) return;
    } catch (error) {
      debugPrint(
        'Aktualität der Turnieransage konnte nicht geprüft werden: $error',
      );
      return;
    }
    await _runAudioOperation(
      'Deutsche Turnieransage',
      () => _output.speakGerman(text),
    );
    for (final alternative in allAlternatives) {
      if (requestId != _requestId) return;
      try {
        if (!isStillCurrent()) return;
      } catch (error) {
        debugPrint(
          'Aktualität der alternativen Turnieransage konnte nicht geprüft werden: $error',
        );
        return;
      }
      try {
        await _delay(const Duration(milliseconds: 500));
      } catch (error) {
        debugPrint('Wartezeit vor Alternativansage fehlgeschlagen: $error');
        return;
      }
      if (requestId != _requestId) return;
      try {
        if (!isStillCurrent()) return;
      } catch (error) {
        debugPrint(
          'Aktualität der alternativen Turnieransage konnte nicht geprüft werden: $error',
        );
        return;
      }
      await _runAudioOperation(
        'Alternative deutsche Turnieransage',
        () => _output.speakGerman(alternative),
      );
    }
  }

  void cancel() {
    _requestId++;
    unawaited(
      _runAudioOperation('Sprachausgabe abbrechen', _output.stopSpeaking),
    );
  }

  Future<void> dispose() async {
    _requestId++;
    await _runAudioOperation('Sprachausgabe stoppen', _output.stopSpeaking);
    await _runAudioOperation('Audioausgabe freigeben', _output.dispose);
  }

  Future<void> _runAudioOperation(
    String description,
    Future<void> Function() operation,
  ) async {
    try {
      await operation();
    } catch (error) {
      debugPrint('$description fehlgeschlagen: $error');
    }
  }
}

class _LocalTournamentAnnouncementAudioOutput
    implements TournamentAnnouncementAudioOutput {
  _LocalTournamentAnnouncementAudioOutput()
    : _player = AudioPlayer(),
      _tts = FlutterTts();

  final AudioPlayer _player;
  final FlutterTts _tts;

  @override
  Future<void> playCue() async {
    final completed = _player.onPlayerComplete.first;
    await _player.play(BytesSource(_createSignalWave()));
    await completed.timeout(const Duration(seconds: 2));
  }

  @override
  Future<void> speakGerman(String text) async {
    await _tts.setLanguage('de-DE');
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await _preferInstalledGermanVoice();
    }
    await _tts.setSpeechRate(0.42);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);
    await _tts.speak(text);
  }

  Future<void> _preferInstalledGermanVoice() async {
    try {
      final voices = await _tts.getVoices;
      final germanVoices = voices
          .where(
            (voice) =>
                voice['locale']?.toLowerCase().startsWith('de') == true &&
                voice['name']?.toLowerCase().contains('online') != true,
          )
          .toList();
      final voice =
          germanVoices
              .where(
                (candidate) =>
                    candidate['name']?.toLowerCase().contains('natural') ==
                    true,
              )
              .firstOrNull ??
          germanVoices.firstOrNull;
      if (voice != null) {
        await _tts.setVoice({
          'locale': voice['locale']!,
          'name': voice['name']!,
        });
      }
    } catch (error) {
      debugPrint('Lokale deutsche Stimme konnte nicht gewählt werden: $error');
    }
  }

  @override
  Future<void> stopSpeaking() => _tts.stop();

  @override
  Future<void> dispose() async {
    await _player.dispose();
    await _tts.stop();
  }

  Uint8List _createSignalWave() {
    const sampleRate = 22050;
    const sampleCount = sampleRate ~/ 10;
    const pcmBytes = sampleCount * 2;
    final wave = ByteData(44 + pcmBytes);

    void writeAscii(int offset, String value) {
      for (var index = 0; index < value.length; index++) {
        wave.setUint8(offset + index, value.codeUnitAt(index));
      }
    }

    writeAscii(0, 'RIFF');
    wave.setUint32(4, 36 + pcmBytes, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    wave.setUint32(16, 16, Endian.little);
    wave.setUint16(20, 1, Endian.little);
    wave.setUint16(22, 1, Endian.little);
    wave.setUint32(24, sampleRate, Endian.little);
    wave.setUint32(28, sampleRate * 2, Endian.little);
    wave.setUint16(32, 2, Endian.little);
    wave.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    wave.setUint32(40, pcmBytes, Endian.little);

    for (var index = 0; index < sampleCount; index++) {
      final fadeIn = math.min(1.0, index / 220);
      final fadeOut = math.min(1.0, (sampleCount - index - 1) / 220);
      final envelope = math.min(fadeIn, fadeOut);
      final sample =
          (math.sin(2 * math.pi * 880 * index / sampleRate) * 12000 * envelope)
              .round();
      wave.setInt16(44 + index * 2, sample, Endian.little);
    }

    return wave.buffer.asUint8List();
  }
}
