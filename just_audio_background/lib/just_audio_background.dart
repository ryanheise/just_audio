import 'just_audio_background_plugin.dart';

class JustAudioBackground {
  static Future<void> init() async {
    await JustAudioBackgroundPlugin.setup();
  }
}
