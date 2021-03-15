import 'dart:async';
import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel_just_audio.dart';

/// The interface that implementations of just_audio must implement.
///
/// Platform implementations should extend this class rather than implement it
/// as `just_audio` does not consider newly added methods to be breaking
/// changes. Extending this class (using `extends`) ensures that the subclass
/// will get the default implementation, while platform implementations that
/// `implements` this interface will be broken by newly added
/// [JustAudioPlatform] methods.
abstract class JustAudioPlatform extends PlatformInterface {
  /// Constructs a JustAudioPlatform.
  JustAudioPlatform() : super(token: _token);

  static final Object _token = Object();

  static JustAudioPlatform _instance = MethodChannelJustAudio();

  /// The default instance of [JustAudioPlatform] to use.
  ///
  /// Defaults to [MethodChannelJustAudio].
  static JustAudioPlatform get instance => _instance;

  /// Platform-specific plugins should set this with their own platform-specific
  /// class that extends [JustAudioPlatform] when they register themselves.
  // TODO(amirh): Extract common platform interface logic.
  // https://github.com/flutter/flutter/issues/43368
  static set instance(JustAudioPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Creates a new platform player and returns a nested platform interface for
  /// communicating with that player.
  Future<AudioPlayerPlatform> init(InitRequest request) {
    throw UnimplementedError('init() has not been implemented.');
  }

  /// Disposes of a platform player.
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) {
    throw UnimplementedError('disposePlayer() has not been implemented.');
  }
}

/// A nested platform interface for communicating with a particular player
/// instance.
///
/// Platform implementations should extend this class rather than implement it
/// as `just_audio` does not consider newly added methods to be breaking
/// changes. Extending this class (using `extends`) ensures that the subclass
/// will get the default implementation, while platform implementations that
/// `implements` this interface will be broken by newly added
/// [AudioPlayerPlatform] methods.
abstract class AudioPlayerPlatform {
  final String id;

  AudioPlayerPlatform(this.id);

  /// A stream of playback events.
  Stream<PlaybackEventMessage> get playbackEventMessageStream {
    throw UnimplementedError(
        'playbackEventMessageStream has not been implemented.');
  }

  /// A stream of visualizer waveform data.
  Stream<VisualizerWaveformCaptureMessage> get visualizerWaveformStream {
    throw UnimplementedError(
        'visualizerWaveformStream has not been implemented.');
  }

  /// A stream of visualizer fft data.
  Stream<VisualizerFftCaptureMessage> get visualizerFftStream {
    throw UnimplementedError('visualizerFftStream has not been implemented.');
  }

  /// Loads an audio source.
  Future<LoadResponse> load(LoadRequest request) {
    throw UnimplementedError("load() has not been implemented.");
  }

  /// Plays the current audio source at the current index and position.
  Future<PlayResponse> play(PlayRequest request) {
    throw UnimplementedError("play() has not been implemented.");
  }

  /// Pauses playback.
  Future<PauseResponse> pause(PauseRequest request) {
    throw UnimplementedError("pause() has not been implemented.");
  }

  /// Changes the volume.
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) {
    throw UnimplementedError("setVolume() has not been implemented.");
  }

  /// Changes the playback speed.
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) {
    throw UnimplementedError("setSpeed() has not been implemented.");
  }

  /// Changes the pitch.
  Future<SetPitchResponse> setPitch(SetPitchRequest request) {
    throw UnimplementedError("setPitch() has not been implemented.");
  }

  /// sets skipSilence to true/false.
  Future<SetSkipSilenceResponse> setSkipSilence(SetSkipSilenceRequest request) {
    throw UnimplementedError("setSkipSilence() has not been implemented.");
  }

  /// Sets the loop mode.
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) {
    throw UnimplementedError("setLoopMode() has not been implemented.");
  }

  /// Sets the shuffle mode.
  Future<SetShuffleModeResponse> setShuffleMode(SetShuffleModeRequest request) {
    throw UnimplementedError("setShuffleMode() has not been implemented.");
  }

  /// Sets the shuffle order.
  Future<SetShuffleOrderResponse> setShuffleOrder(
      SetShuffleOrderRequest request) {
    throw UnimplementedError("setShuffleOrder() has not been implemented.");
  }

  /// On iOS and macOS, sets the automaticallyWaitsToMinimizeStalling option,
  /// and does nothing on other platforms.
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
      setAutomaticallyWaitsToMinimizeStalling(
          SetAutomaticallyWaitsToMinimizeStallingRequest request) {
    throw UnimplementedError(
        "setAutomaticallyWaitsToMinimizeStalling() has not been implemented.");
  }

  /// On iOS and macOS, sets the
  /// canUseNetworkResourcesForLiveStreamingWhilePaused option, and does nothing
  /// on other platforms.
  Future<SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse>
      setCanUseNetworkResourcesForLiveStreamingWhilePaused(
          SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest request) {
    throw UnimplementedError(
        "setCanUseNetworkResourcesForLiveStreamingWhilePaused() has not been implemented.");
  }

  /// On iOS and macOS, sets the preferredPeakBitRate option, and does nothing
  /// on other platforms.
  Future<SetPreferredPeakBitRateResponse> setPreferredPeakBitRate(
      SetPreferredPeakBitRateRequest request) {
    throw UnimplementedError(
        "setPreferredPeakBitRate() has not been implemented.");
  }

  /// Seeks to the given index and position.
  Future<SeekResponse> seek(SeekRequest request) {
    throw UnimplementedError("seek() has not been implemented.");
  }

  /// On Android, sets the audio attributes, and does nothing on other
  /// platforms.
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
      SetAndroidAudioAttributesRequest request) {
    throw UnimplementedError(
        "setAndroidAudioAttributes() has not been implemented.");
  }

  /// This method has been superceded by [JustAudioPlatform.disposePlayer].
  /// For backward compatibility, this method will still be called as a
  /// fallback if [JustAudioPlatform.disposePlayer] is not implemented.
  Future<DisposeResponse> dispose(DisposeRequest request) {
    throw UnimplementedError("dispose() has not been implemented.");
  }

  /// Inserts audio sources into the given concatenating audio source.
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
      ConcatenatingInsertAllRequest request) {
    throw UnimplementedError(
        "concatenatingInsertAll() has not been implemented.");
  }

  /// Removes audio sources from the given concatenating audio source.
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
      ConcatenatingRemoveRangeRequest request) {
    throw UnimplementedError(
        "concatenatingRemoveRange() has not been implemented.");
  }

  /// Moves an audio source within a concatenating audio source.
  Future<ConcatenatingMoveResponse> concatenatingMove(
      ConcatenatingMoveRequest request) {
    throw UnimplementedError("concatenatingMove() has not been implemented.");
  }

  /// Starts the visualizer.
  Future<StartVisualizerResponse> startVisualizer(
      StartVisualizerRequest request) {
    throw UnimplementedError("startVisualizer() has not been implemented.");
  }

  /// Stops the visualizer.
  Future<StopVisualizerResponse> stopVisualizer(StopVisualizerRequest request) {
    throw UnimplementedError("stopVisualizer() has not been implemented.");
  }
}

/// A playback event communicated from the platform implementation to the
/// Flutter plugin.
class PlaybackEventMessage {
  final ProcessingStateMessage processingState;
  final DateTime updateTime;
  final Duration updatePosition;
  final Duration bufferedPosition;
  final Duration? duration;
  final IcyMetadataMessage? icyMetadata;
  final int? currentIndex;
  final int? androidAudioSessionId;

  PlaybackEventMessage({
    required this.processingState,
    required this.updateTime,
    required this.updatePosition,
    required this.bufferedPosition,
    required this.duration,
    required this.icyMetadata,
    required this.currentIndex,
    required this.androidAudioSessionId,
  });

  static PlaybackEventMessage fromMap(Map<dynamic, dynamic> map) =>
      PlaybackEventMessage(
        processingState:
            ProcessingStateMessage.values[map['processingState'] as int],
        updateTime:
            DateTime.fromMillisecondsSinceEpoch(map['updateTime'] as int),
        updatePosition: Duration(microseconds: map['updatePosition'] as int),
        bufferedPosition:
            Duration(microseconds: map['bufferedPosition'] as int),
        duration: map['duration'] == null || map['duration'] as int < 0
            ? null
            : Duration(microseconds: map['duration'] as int),
        icyMetadata: map['icyMetadata'] == null
            ? null
            : IcyMetadataMessage.fromMap(
                map['icyMetadata'] as Map<dynamic, dynamic>),
        currentIndex: map['currentIndex'] as int?,
        androidAudioSessionId: map['androidAudioSessionId'] as int?,
      );
}

/// A processing state communicated from the platform implementation.
enum ProcessingStateMessage {
  idle,
  loading,
  buffering,
  ready,
  completed,
}

/// Icy metadata communicated from the platform implementation.
class IcyMetadataMessage {
  final IcyInfoMessage? info;
  final IcyHeadersMessage? headers;

  IcyMetadataMessage({
    required this.info,
    required this.headers,
  });

  static IcyMetadataMessage fromMap(Map<dynamic, dynamic> json) =>
      IcyMetadataMessage(
        info: json['info'] == null
            ? null
            : IcyInfoMessage.fromMap(json['info'] as Map<dynamic, dynamic>),
        headers: json['headers'] == null
            ? null
            : IcyHeadersMessage.fromMap(
                json['headers'] as Map<dynamic, dynamic>),
      );
}

/// Icy info communicated from the platform implementation.
class IcyInfoMessage {
  final String? title;
  final String? url;

  IcyInfoMessage({
    required this.title,
    required this.url,
  });

  static IcyInfoMessage fromMap(Map<dynamic, dynamic> json) => IcyInfoMessage(
      title: json['title'] as String?, url: json['url'] as String?);
}

/// Icy headers communicated from the platform implementation.
class IcyHeadersMessage {
  final int? bitrate;
  final String? genre;
  final String? name;
  final int? metadataInterval;
  final String? url;
  final bool? isPublic;

  IcyHeadersMessage({
    required this.bitrate,
    required this.genre,
    required this.name,
    required this.metadataInterval,
    required this.url,
    required this.isPublic,
  });

  static IcyHeadersMessage fromMap(Map<dynamic, dynamic> json) =>
      IcyHeadersMessage(
        bitrate: json['bitrate'] as int?,
        genre: json['genre'] as String?,
        name: json['name'] as String?,
        metadataInterval: json['metadataInterval'] as int?,
        url: json['url'] as String?,
        isPublic: json['isPublic'] as bool?,
      );
}

/// Information communicated to the platform implementation when creating a new
/// player instance.
class InitRequest {
  final String id;
  final AudioLoadConfigurationMessage? audioLoadConfiguration;

  InitRequest({required this.id, this.audioLoadConfiguration});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'id': id,
        'audioLoadConfiguration': audioLoadConfiguration?.toMap(),
      };
}

/// Information communicated to the platform implementation when disposing of a
/// player instance.
class DisposePlayerRequest {
  final String id;

  DisposePlayerRequest({required this.id});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'id': id,
      };
}

/// Information returned by the platform implementation after disposing of a
/// player instance.
class DisposePlayerResponse {
  static DisposePlayerResponse fromMap(Map<dynamic, dynamic> map) =>
      DisposePlayerResponse();
}

/// Information communicated to the platform implementation when loading an
/// audio source.
class LoadRequest {
  final AudioSourceMessage audioSourceMessage;
  final Duration? initialPosition;
  final int? initialIndex;

  LoadRequest({
    required this.audioSourceMessage,
    this.initialPosition,
    this.initialIndex,
  });

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'audioSource': audioSourceMessage.toMap(),
        'initialPosition': initialPosition?.inMicroseconds,
        'initialIndex': initialIndex,
      };
}

/// Information returned by the platform implementation after loading an audio
/// source.
class LoadResponse {
  final Duration? duration;

  LoadResponse({required this.duration});

  static LoadResponse fromMap(Map<dynamic, dynamic> map) => LoadResponse(
      duration: map['duration'] == null || map['duration'] as int < 0
          ? null
          : Duration(microseconds: map['duration'] as int));
}

/// Information communicated to the platform implementation when playing an
/// audio source.
class PlayRequest {
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{};
}

/// Information returned by the platform implementation after playing an audio
/// source.
class PlayResponse {
  static PlayResponse fromMap(Map<dynamic, dynamic> map) => PlayResponse();
}

/// Information communicated to the platform implementation when pausing
/// playback.
class PauseRequest {
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{};
}

/// Information returned by the platform implementation after pausing playback.
class PauseResponse {
  static PauseResponse fromMap(Map<dynamic, dynamic> map) => PauseResponse();
}

/// Information communicated to the platform implementation when setting the
/// volume.
class SetVolumeRequest {
  final double volume;

  SetVolumeRequest({required this.volume});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'volume': volume,
      };
}

/// Information returned by the platform implementation after setting the
/// volume.
class SetVolumeResponse {
  static SetVolumeResponse fromMap(Map<dynamic, dynamic> map) =>
      SetVolumeResponse();
}

/// Information communicated to the platform implementation when setting the
/// speed.
class SetSpeedRequest {
  final double speed;

  SetSpeedRequest({required this.speed});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'speed': speed,
      };
}

/// Information returned by the platform implementation after setting the
/// speed.
class SetSpeedResponse {
  static SetSpeedResponse fromMap(Map<dynamic, dynamic> map) =>
      SetSpeedResponse();
}

/// Information communicated to the platform implementation when setting the
/// pitch.
class SetPitchRequest {
  final double pitch;

  SetPitchRequest({required this.pitch});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'pitch': pitch,
      };
}

/// Information returned by the platform implementation after setting the
/// pitch.
class SetPitchResponse {
  static SetPitchResponse fromMap(Map<dynamic, dynamic> map) =>
      SetPitchResponse();
}

/// Information communicated to the platform implementation when setting the
/// skipSilence.
class SetSkipSilenceRequest {
  final bool enabled;

  SetSkipSilenceRequest({required this.enabled});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'enabled': enabled,
      };
}

/// Information returned by the platform implementation after setting the
/// speed.
class SetSkipSilenceResponse {
  static SetSkipSilenceResponse fromMap(Map<dynamic, dynamic> map) =>
      SetSkipSilenceResponse();
}

/// Information communicated to the platform implementation when setting the
/// loop mode.
class SetLoopModeRequest {
  final LoopModeMessage loopMode;

  SetLoopModeRequest({required this.loopMode});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'loopMode': loopMode.index,
      };
}

/// Information returned by the platform implementation after setting the
/// loop mode.
class SetLoopModeResponse {
  static SetLoopModeResponse fromMap(Map<dynamic, dynamic> map) =>
      SetLoopModeResponse();
}

/// The loop mode communicated to the platform implementation.
enum LoopModeMessage { off, one, all }

/// Information communicated to the platform implementation when setting the
/// shuffle mode.
class SetShuffleModeRequest {
  final ShuffleModeMessage shuffleMode;

  SetShuffleModeRequest({required this.shuffleMode});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'shuffleMode': shuffleMode.index,
      };
}

/// Information returned by the platform implementation after setting the
/// shuffle mode.
class SetShuffleModeResponse {
  static SetShuffleModeResponse fromMap(Map<dynamic, dynamic> map) =>
      SetShuffleModeResponse();
}

/// The shuffle mode communicated to the platform implementation.
enum ShuffleModeMessage { none, all }

/// Information communicated to the platform implementation when setting the
/// shuffle order.
class SetShuffleOrderRequest {
  final AudioSourceMessage audioSourceMessage;

  SetShuffleOrderRequest({required this.audioSourceMessage});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'audioSource': audioSourceMessage.toMap(),
      };
}

/// Information returned by the platform implementation after setting the
/// shuffle order.
class SetShuffleOrderResponse {
  static SetShuffleOrderResponse fromMap(Map<dynamic, dynamic> map) =>
      SetShuffleOrderResponse();
}

/// Information communicated to the platform implementation when setting the
/// automaticallyWaitsToMinimizeStalling option.
class SetAutomaticallyWaitsToMinimizeStallingRequest {
  final bool enabled;

  SetAutomaticallyWaitsToMinimizeStallingRequest({required this.enabled});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'enabled': enabled,
      };
}

/// Information returned by the platform implementation after setting the
/// automaticallyWaitsToMinimizeStalling option.
class SetAutomaticallyWaitsToMinimizeStallingResponse {
  static SetAutomaticallyWaitsToMinimizeStallingResponse fromMap(
          Map<dynamic, dynamic> map) =>
      SetAutomaticallyWaitsToMinimizeStallingResponse();
}

/// Information communicated to the platform implementation when setting the
/// canUseNetworkResourcesForLiveStreamingWhilePaused option.
class SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest {
  final bool enabled;

  SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest(
      {required this.enabled});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'enabled': enabled,
      };
}

/// Information returned by the platform implementation after setting the
/// canUseNetworkResourcesForLiveStreamingWhilePaused option.
class SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse {
  static SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse fromMap(
          Map<dynamic, dynamic> map) =>
      SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse();
}

/// Information communicated to the platform implementation when setting the
/// automaticallyWaitsToMinimizeStalling option.
class SetPreferredPeakBitRateRequest {
  final double bitRate;

  SetPreferredPeakBitRateRequest({required this.bitRate});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'bitRate': bitRate,
      };
}

/// Information returned by the platform implementation after setting the
/// automaticallyWaitsToMinimizeStalling option.
class SetPreferredPeakBitRateResponse {
  static SetPreferredPeakBitRateResponse fromMap(Map<dynamic, dynamic> map) =>
      SetPreferredPeakBitRateResponse();
}

/// Information communicated to the platform implementation when seeking to a
/// position and index.
class SeekRequest {
  final Duration? position;
  final int? index;

  SeekRequest({this.position, this.index});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'position': position?.inMicroseconds,
        'index': index,
      };
}

/// Information returned by the platform implementation after seeking to a
/// position and index.
class SeekResponse {
  static SeekResponse fromMap(Map<dynamic, dynamic> map) => SeekResponse();
}

/// Information communicated to the platform implementation when setting the
/// Android audio attributes.
class SetAndroidAudioAttributesRequest {
  final int contentType;
  final int flags;
  final int usage;

  SetAndroidAudioAttributesRequest({
    required this.contentType,
    required this.flags,
    required this.usage,
  });

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'contentType': contentType,
        'flags': flags,
        'usage': usage,
      };
}

/// Information returned by the platform implementation after setting the
/// Android audio attributes.
class SetAndroidAudioAttributesResponse {
  static SetAndroidAudioAttributesResponse fromMap(Map<dynamic, dynamic> map) =>
      SetAndroidAudioAttributesResponse();
}

/// The parameter of [AudioPlayerPlatform.dispose] which is deprecated.
class DisposeRequest {
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{};
}

/// The result of [AudioPlayerPlatform.dispose] which is deprecated.
class DisposeResponse {
  static DisposeResponse fromMap(Map<dynamic, dynamic> map) =>
      DisposeResponse();
}

/// Information communicated to the platform implementation when inserting audio
/// sources into a concatenating audio source.
class ConcatenatingInsertAllRequest {
  final String id;
  final int index;
  final List<AudioSourceMessage> children;
  final List<int> shuffleOrder;

  ConcatenatingInsertAllRequest({
    required this.id,
    required this.index,
    required this.children,
    required this.shuffleOrder,
  });

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'id': id,
        'index': index,
        'children': children.map((child) => child.toMap()).toList(),
        'shuffleOrder': shuffleOrder,
      };
}

/// Information returned by the platform implementation after inserting audio
/// sources into a concatenating audio source.
class ConcatenatingInsertAllResponse {
  static ConcatenatingInsertAllResponse fromMap(Map<dynamic, dynamic> map) =>
      ConcatenatingInsertAllResponse();
}

/// Information communicated to the platform implementation when removing audio
/// sources from a concatenating audio source.
class ConcatenatingRemoveRangeRequest {
  final String id;
  final int startIndex;
  final int endIndex;
  final List<int> shuffleOrder;

  ConcatenatingRemoveRangeRequest({
    required this.id,
    required this.startIndex,
    required this.endIndex,
    required this.shuffleOrder,
  });

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'id': id,
        'startIndex': startIndex,
        'endIndex': endIndex,
        'shuffleOrder': shuffleOrder,
      };
}

/// Information returned by the platform implementation after removing audio
/// sources from a concatenating audio source.
class ConcatenatingRemoveRangeResponse {
  static ConcatenatingRemoveRangeResponse fromMap(Map<dynamic, dynamic> map) =>
      ConcatenatingRemoveRangeResponse();
}

/// Information communicated to the platform implementation when moving an audio
/// source within a concatenating audio source.
class ConcatenatingMoveRequest {
  final String id;
  final int currentIndex;
  final int newIndex;
  final List<int> shuffleOrder;

  ConcatenatingMoveRequest({
    required this.id,
    required this.currentIndex,
    required this.newIndex,
    required this.shuffleOrder,
  });

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'id': id,
        'currentIndex': currentIndex,
        'newIndex': newIndex,
        'shuffleOrder': shuffleOrder,
      };
}

/// Information returned by the platform implementation after moving an audio
/// source within a concatenating audio source.
class ConcatenatingMoveResponse {
  static ConcatenatingMoveResponse fromMap(Map<dynamic, dynamic> map) =>
      ConcatenatingMoveResponse();
}

/// Information communicated to the platform implementation when starting the
/// visualizer.
class StartVisualizerRequest {
  final bool enableWaveform;
  final bool enableFft;
  final int? captureRate;
  final int? captureSize;

  StartVisualizerRequest({
    required this.enableWaveform,
    required this.enableFft,
    required this.captureRate,
    required this.captureSize,
  });

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'enableWaveform': enableWaveform,
        'enableFft': enableFft,
        'captureRate': captureRate,
        'captureSize': captureSize,
      };
}

/// Information returned by the platform implementation after starting the
/// visualizer.
class StartVisualizerResponse {
  StartVisualizerResponse();

  static StartVisualizerResponse fromMap(Map<dynamic, dynamic> map) =>
      StartVisualizerResponse();
}

/// Information communicated to the platform implementation when stopping the
/// visualizer.
class StopVisualizerRequest {
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{};
}

/// Information returned by the platform implementation after stopping the
/// visualizer.
class StopVisualizerResponse {
  static StopVisualizerResponse fromMap(Map<dynamic, dynamic> map) =>
      StopVisualizerResponse();
}

/// A capture of audio waveform data.
class VisualizerWaveformCaptureMessage {
  /// The sampling rate of the capture.
  final int samplingRate;

  /// The waveform data.
  final Uint8List data;

  VisualizerWaveformCaptureMessage({
    required this.samplingRate,
    required this.data,
  });
}

/// A capture of audio FFT data.
class VisualizerFftCaptureMessage {
  /// The sampling rate of the capture.
  final int samplingRate;

  /// The FFT data.
  final Uint8List data;

  VisualizerFftCaptureMessage({
    required this.samplingRate,
    required this.data,
  });
}

/// Information communicated to the platform implementation when setting the
/// audio load configuration options.
class AudioLoadConfigurationMessage {
  final DarwinLoadControlMessage? darwinLoadControl;
  final AndroidLoadControlMessage? androidLoadControl;
  final AndroidLivePlaybackSpeedControlMessage? androidLivePlaybackSpeedControl;

  const AudioLoadConfigurationMessage({
    required this.darwinLoadControl,
    required this.androidLoadControl,
    required this.androidLivePlaybackSpeedControl,
  });

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'darwinLoadControl': darwinLoadControl?.toMap(),
        'androidLoadControl': androidLoadControl?.toMap(),
        'androidLivePlaybackSpeedControl':
            androidLivePlaybackSpeedControl?.toMap(),
      };
}

class DarwinLoadControlMessage {
  /// (iOS/macOS) Whether the player will wait for sufficient data to be
  /// buffered before starting playback to avoid the likelihood of stalling.
  final bool automaticallyWaitsToMinimizeStalling;

  /// (iOS/macOS) The duration of audio that should be buffered ahead of the
  /// current position. If not set or `null`, the system will try to set an
  /// appropriate buffer duration.
  final Duration? preferredForwardBufferDuration;

  /// (iOS/macOS) Whether the player can continue downloading while paused to
  /// keep the state up to date with the live stream.
  final bool canUseNetworkResourcesForLiveStreamingWhilePaused;

  /// (iOS/macOS) If specified, limits the download bandwidth in bits per
  /// second.
  final double? preferredPeakBitRate;

  DarwinLoadControlMessage({
    required this.automaticallyWaitsToMinimizeStalling,
    required this.preferredForwardBufferDuration,
    required this.canUseNetworkResourcesForLiveStreamingWhilePaused,
    required this.preferredPeakBitRate,
  });

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'automaticallyWaitsToMinimizeStalling':
            automaticallyWaitsToMinimizeStalling,
        'preferredForwardBufferDuration':
            preferredForwardBufferDuration?.inMicroseconds,
        'canUseNetworkResourcesForLiveStreamingWhilePaused':
            canUseNetworkResourcesForLiveStreamingWhilePaused,
        'preferredPeakBitRate': preferredPeakBitRate,
      };
}

class AndroidLoadControlMessage {
  /// (Android) The minimum duration of audio that should be buffered ahead of
  /// the current position.
  final Duration minBufferDuration;

  /// (Android) The maximum duration of audio that should be buffered ahead of
  /// the current position.
  final Duration maxBufferDuration;

  /// (Android) The duration of audio that must be buffered before starting
  /// playback after a user action.
  final Duration bufferForPlaybackDuration;

  /// (Android) The duration of audio that must be buffered before starting
  /// playback after a buffer depletion.
  final Duration bufferForPlaybackAfterRebufferDuration;

  /// (Android) The target buffer size in bytes.
  final int? targetBufferBytes;

  /// (Android) Whether to prioritize buffer time constraints over buffer size
  /// constraints.
  final bool prioritizeTimeOverSizeThresholds;

  /// (Android) The back buffer duration.
  final Duration backBufferDuration;

  AndroidLoadControlMessage({
    required this.minBufferDuration,
    required this.maxBufferDuration,
    required this.bufferForPlaybackDuration,
    required this.bufferForPlaybackAfterRebufferDuration,
    required this.targetBufferBytes,
    required this.prioritizeTimeOverSizeThresholds,
    required this.backBufferDuration,
  });

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'minBufferDuration': minBufferDuration.inMicroseconds,
        'maxBufferDuration': maxBufferDuration.inMicroseconds,
        'bufferForPlaybackDuration': bufferForPlaybackDuration.inMicroseconds,
        'bufferForPlaybackAfterRebufferDuration':
            bufferForPlaybackAfterRebufferDuration.inMicroseconds,
        'targetBufferBytes': targetBufferBytes,
        'prioritizeTimeOverSizeThresholds': prioritizeTimeOverSizeThresholds,
        'backBufferDuration': backBufferDuration.inMicroseconds,
      };
}

class AndroidLivePlaybackSpeedControlMessage {
  /// (Android) The minimum playback speed to use when adjusting playback speed
  /// to approach the target live offset, if none is defined by the media.
  final double fallbackMinPlaybackSpeed;

  /// (Android) The maximum playback speed to use when adjusting playback speed
  /// to approach the target live offset, if none is defined by the media.
  final double fallbackMaxPlaybackSpeed;

  /// (Android) The minimum interval between playback speed changes on a live
  /// stream.
  final Duration minUpdateInterval;

  /// (Android) The proportional control factor used to adjust playback speed on
  /// a live stream. The adjusted speed is calculated as: `1.0 +
  /// proportionalControlFactor * (currentLiveOffsetSec - targetLiveOffsetSec)`.
  final double proportionalControlFactor;

  /// (Android) The maximum difference between the current live offset and the
  /// target live offset within which the speed 1.0 is used.
  final Duration maxLiveOffsetErrorForUnitSpeed;

  /// (Android) The increment applied to the target live offset whenever the
  /// player rebuffers.
  final Duration targetLiveOffsetIncrementOnRebuffer;

  /// (Android) The factor for smoothing the minimum possible live offset
  /// achievable during playback.
  final double minPossibleLiveOffsetSmoothingFactor;

  AndroidLivePlaybackSpeedControlMessage({
    required this.fallbackMinPlaybackSpeed,
    required this.fallbackMaxPlaybackSpeed,
    required this.minUpdateInterval,
    required this.proportionalControlFactor,
    required this.maxLiveOffsetErrorForUnitSpeed,
    required this.targetLiveOffsetIncrementOnRebuffer,
    required this.minPossibleLiveOffsetSmoothingFactor,
  });

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'fallbackMinPlaybackSpeed': fallbackMinPlaybackSpeed,
        'fallbackMaxPlaybackSpeed': fallbackMaxPlaybackSpeed,
        'minUpdateInterval': minUpdateInterval.inMicroseconds,
        'proportionalControlFactor': proportionalControlFactor,
        'maxLiveOffsetErrorForUnitSpeed':
            maxLiveOffsetErrorForUnitSpeed.inMicroseconds,
        'targetLiveOffsetIncrementOnRebuffer':
            targetLiveOffsetIncrementOnRebuffer.inMicroseconds,
        'minPossibleLiveOffsetSmoothingFactor':
            minPossibleLiveOffsetSmoothingFactor,
      };
}

/// Information about an audio source to be communicated with the platform
/// implementation.
abstract class AudioSourceMessage {
  final String id;

  AudioSourceMessage({required this.id});

  Map<dynamic, dynamic> toMap();
}

/// Information about an indexed audio source to be communicated with the
/// platform implementation.
abstract class IndexedAudioSourceMessage extends AudioSourceMessage {
  IndexedAudioSourceMessage({required String id}) : super(id: id);
}

/// Information about a URI audio source to be communicated with the platform
/// implementation.
abstract class UriAudioSourceMessage extends IndexedAudioSourceMessage {
  final String uri;
  final Map<dynamic, dynamic>? headers;

  UriAudioSourceMessage({
    required String id,
    required this.uri,
    this.headers,
  }) : super(id: id);
}

/// Information about a progressive audio source to be communicated with the
/// platform implementation.
class ProgressiveAudioSourceMessage extends UriAudioSourceMessage {
  ProgressiveAudioSourceMessage({
    required String id,
    required String uri,
    Map<dynamic, dynamic>? headers,
  }) : super(id: id, uri: uri, headers: headers);

  @override
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'type': 'progressive',
        'id': id,
        'uri': uri,
        'headers': headers,
      };
}

/// Information about a DASH audio source to be communicated with the platform
/// implementation.
class DashAudioSourceMessage extends UriAudioSourceMessage {
  DashAudioSourceMessage({
    required String id,
    required String uri,
    Map<dynamic, dynamic>? headers,
  }) : super(id: id, uri: uri, headers: headers);

  @override
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'type': 'dash',
        'id': id,
        'uri': uri,
        'headers': headers,
      };
}

/// Information about a HLS audio source to be communicated with the platform
/// implementation.
class HlsAudioSourceMessage extends UriAudioSourceMessage {
  HlsAudioSourceMessage({
    required String id,
    required String uri,
    Map<dynamic, dynamic>? headers,
  }) : super(id: id, uri: uri, headers: headers);

  @override
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'type': 'hls',
        'id': id,
        'uri': uri,
        'headers': headers,
      };
}

/// Information about a concatenating audio source to be communicated with the
/// platform implementation.
class ConcatenatingAudioSourceMessage extends AudioSourceMessage {
  final List<AudioSourceMessage> children;
  final bool useLazyPreparation;
  final List<int> shuffleOrder;

  ConcatenatingAudioSourceMessage({
    required String id,
    required this.children,
    required this.useLazyPreparation,
    required this.shuffleOrder,
  }) : super(id: id);

  @override
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'type': 'concatenating',
        'id': id,
        'children': children.map((child) => child.toMap()).toList(),
        'useLazyPreparation': useLazyPreparation,
        'shuffleOrder': shuffleOrder,
      };
}

/// Information about a clipping audio source to be communicated with the
/// platform implementation.
class ClippingAudioSourceMessage extends IndexedAudioSourceMessage {
  final UriAudioSourceMessage child;
  final Duration? start;
  final Duration? end;

  ClippingAudioSourceMessage({
    required String id,
    required this.child,
    this.start,
    this.end,
  }) : super(id: id);

  @override
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'type': 'clipping',
        'id': id,
        'child': child.toMap(),
        'start': start?.inMicroseconds,
        'end': end?.inMicroseconds,
      };
}

/// Information about a looping audio source to be communicated with the
/// platform implementation.
class LoopingAudioSourceMessage extends AudioSourceMessage {
  final AudioSourceMessage child;
  final int count;

  LoopingAudioSourceMessage({
    required String id,
    required this.child,
    required this.count,
  }) : super(id: id);

  @override
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'type': 'looping',
        'id': id,
        'child': child.toMap(),
        'count': count,
      };
}
