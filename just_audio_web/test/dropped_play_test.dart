@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:just_audio_web/just_audio_web.dart';

/// A silent 8 kHz, 8-bit mono WAV of [ms] milliseconds, as a data: URI.
String _silentWav(int ms) {
  final samples = 8 * ms;
  final bytes = ByteData(44 + samples);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + samples, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 1, Endian.little); // mono
  bytes.setUint32(24, 8000, Endian.little);
  bytes.setUint32(28, 8000, Endian.little);
  bytes.setUint16(32, 1, Endian.little);
  bytes.setUint16(34, 8, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, samples, Endian.little);
  for (var i = 0; i < samples; i++) {
    bytes.setUint8(44 + i, 128);
  }
  return 'data:audio/wav;base64,${base64Encode(bytes.buffer.asUint8List())}';
}

LoadRequest _load(String id) => LoadRequest(
      audioSourceMessage:
          ProgressiveAudioSourceMessage(id: id, uri: _silentWav(2000)),
    );

void main() {
  test('a play() that load() starts on its own does not leak a rejection',
      () async {
    final player = Html5AudioPlayer(id: 'player');
    await player.load(_load('a'));

    // A play request, awaited by its caller; whether the browser allows it
    // does not matter here.
    unawaited(
        player.play(PlayRequest()).then<void>((_) {}, onError: (Object _) {}));

    // While playing, load() starts playback of the new source itself without
    // awaiting it. Pausing straight away interrupts that play() — an
    // AbortError — and a browser that refuses playback outside a gesture
    // rejects it with NotAllowedError either way. Uncaught, either one fails
    // this test through the test zone.
    await player.load(_load('b'));
    await player.pause(PauseRequest());

    await Future<void>.delayed(const Duration(milliseconds: 500));
  });
}
