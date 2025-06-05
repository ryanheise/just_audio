import 'package:just_audio_media_kit/just_audio_media_kit.dart';

void initMediaKit() {
  JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
}
