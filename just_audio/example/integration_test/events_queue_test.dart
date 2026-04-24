import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  final examplePlaylist = [
    AudioSource.uri(
      Uri.parse(
          "https://s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3"),
    ),
    AudioSource.uri(Uri.parse(
        "https://s3.amazonaws.com/scifri-segments/scifri201711241.mp3")),
    AudioSource.uri(
      Uri.parse("asset:///audio/nature.mp3"),
    ),
  ];

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('currentIndexStream emits correct values after set index in setAudioSources()', (
    tester,
  ) async {
    final player = AudioPlayer();
    final queue = StreamQueue<int?>(
      player.currentIndexStream,
    );

    await player.setAudioSources(examplePlaylist, initialIndex: 2);

    await tester.pumpWidget(const MyApp());

    expect(await queue.next, isNull);
    expect(await queue.next, isNull);
    expect(await queue.next, 2);

    await queue.cancel();
  });
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
