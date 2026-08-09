@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:just_audio_web/just_audio_web.dart';

class RecordingHtml5AudioPlayer extends Html5AudioPlayer {
  RecordingHtml5AudioPlayer() : super(id: 'cache-repro');

  final loadedUris = <Uri>[];

  @override
  Future<Duration?> loadUri(Uri uri, Duration? initialPosition) async {
    loadedUris.add(uri);
    return const Duration(minutes: 1);
  }
}

LoadRequest request(String childId, String uri) {
  return LoadRequest(
    audioSourceMessage: ConcatenatingAudioSourceMessage(
      id: '',
      children: [ProgressiveAudioSourceMessage(id: childId, uri: uri)],
      useLazyPreparation: true,
      shuffleOrder: const [0],
    ),
    initialIndex: 0,
  );
}

void main() {
  test(
    'a replacement source tree with the same root ID loads its new URI',
    () async {
      final player = RecordingHtml5AudioPlayer();
      addTearDown(player.release);

      await player.load(request('first', 'https://example.com/first.mp3'));
      await player.load(request('second', 'https://example.com/second.mp3'));

      expect(player.loadedUris, [
        Uri.parse('https://example.com/first.mp3'),
        Uri.parse('https://example.com/second.mp3'),
      ]);
    },
  );
}
