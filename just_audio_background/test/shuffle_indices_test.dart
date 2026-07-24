import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

ProgressiveAudioSourceMessage _uri(String id) =>
    ProgressiveAudioSourceMessage(id: id, uri: 'https://$id.mp3');

ConcatenatingAudioSourceMessage _concat({
  required List<AudioSourceMessage> children,
  required List<int> shuffleOrder,
}) =>
    ConcatenatingAudioSourceMessage(
      id: 'cat',
      children: children,
      useLazyPreparation: true,
      shuffleOrder: shuffleOrder,
    );

void main() {
  test('shuffleIndices returns correct indices for synced shuffleOrder', () {
    final source = _concat(
      children: [_uri('a'), _uri('b'), _uri('c')],
      shuffleOrder: [2, 0, 1],
    );

    expect(source.shuffleIndices, [2, 0, 1]);
  });

  test('shuffleIndices skips out-of-bounds indices in shuffleOrder', () {
    final source = _concat(
      children: [_uri('a'), _uri('b')],
      shuffleOrder: [1, 0, 2],
    );

    expect(source.shuffleIndices, [1, 0]);
  });

  test('shuffleIndices handles all indices out of bounds', () {
    final source = _concat(
      children: [_uri('a')],
      shuffleOrder: [3, 5, 7],
    );

    expect(source.shuffleIndices, isEmpty);
  });
}

