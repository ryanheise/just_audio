import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

void main() {
  test("Init request", () {
    final req = InitRequest(
      id: '123',
      darwinAudioEffects: [],
      audioLoadConfiguration: AudioLoadConfigurationMessage(
        darwinLoadControl: DarwinLoadControlMessage(
            automaticallyWaitsToMinimizeStalling: true,
            canUseNetworkResourcesForLiveStreamingWhilePaused: false,
            preferredForwardBufferDuration: const Duration(),
            preferredPeakBitRate: 0.0),
        androidLivePlaybackSpeedControl: null,
        androidLoadControl: null,
      ),
    );

    expect(req.toMap().toString(), "{id: 123, audioLoadConfiguration: {darwinLoadControl: {automaticallyWaitsToMinimizeStalling: true, preferredForwardBufferDuration: 0, canUseNetworkResourcesForLiveStreamingWhilePaused: false, preferredPeakBitRate: 0.0}, androidLoadControl: null, androidLivePlaybackSpeedControl: null}, androidAudioEffects: [], darwinAudioEffects: [], androidOffloadSchedulingEnabled: null}");
  });
}
