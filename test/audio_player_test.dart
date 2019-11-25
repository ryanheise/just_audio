import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audio_player/audio_player.dart';

void main() {
  const MethodChannel channel = MethodChannel('audio_player');

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('getPlatformVersion', () async {
    expect(await AudioPlayer.platformVersion, '42');
  });
}
