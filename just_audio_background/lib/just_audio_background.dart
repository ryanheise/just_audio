import 'just_audio_background_plugin.dart';

class JustAudioBackground {
  static void init() {
    JustAudioBackgroundPlugin.setup();
  }

  static Future<bool> get running async {
    return await JustAudioBackgroundPlugin.running;
  }
}
