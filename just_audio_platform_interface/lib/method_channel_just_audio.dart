import 'dart:async';

import 'package:flutter/services.dart';

import 'just_audio_platform_interface.dart';

/// An implementation of [JustAudioPlatform] that uses method channels.
class MethodChannelJustAudio extends JustAudioPlatform {
  static final _mainChannel = MethodChannel('com.ryanheise.just_audio.methods');

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    await _mainChannel.invokeMethod('init', request.toMap());
    return MethodChannelAudioPlayer(request.id);
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
      DisposePlayerRequest request) async {
    return DisposePlayerResponse.fromMap(
        await _mainChannel.invokeMethod('disposePlayer', request.toMap()));
  }
}

/// An implementation of [AudioPlayerPlatform] that uses method channels.
class MethodChannelAudioPlayer extends AudioPlayerPlatform {
  final MethodChannel _channel;

  MethodChannelAudioPlayer(String id)
      : _channel = MethodChannel('com.ryanheise.just_audio.methods.$id'),
        super(id);

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      EventChannel('com.ryanheise.just_audio.events.$id')
          .receiveBroadcastStream()
          .map((map) => PlaybackEventMessage.fromMap(map));

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    return LoadResponse.fromMap(
        await _channel.invokeMethod('load', request?.toMap()));
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    return PlayResponse.fromMap(
        await _channel.invokeMethod('play', request?.toMap()));
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    return PauseResponse.fromMap(
        await _channel.invokeMethod('pause', request?.toMap()));
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async {
    return SetVolumeResponse.fromMap(
        await _channel.invokeMethod('setVolume', request?.toMap()));
  }

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async {
    return SetSpeedResponse.fromMap(
        await _channel.invokeMethod('setSpeed', request?.toMap()));
  }

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async {
    return SetLoopModeResponse.fromMap(
        await _channel.invokeMethod('setLoopMode', request?.toMap()));
  }

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
      SetShuffleModeRequest request) async {
    return SetShuffleModeResponse.fromMap(
        await _channel.invokeMethod('setShuffleMode', request?.toMap()));
  }

  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
      setAutomaticallyWaitsToMinimizeStalling(
          SetAutomaticallyWaitsToMinimizeStallingRequest request) async {
    return SetAutomaticallyWaitsToMinimizeStallingResponse.fromMap(
        await _channel.invokeMethod(
            'setAutomaticallyWaitsToMinimizeStalling', request?.toMap()));
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    return SeekResponse.fromMap(
        await _channel.invokeMethod('seek', request?.toMap()));
  }

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
      SetAndroidAudioAttributesRequest request) async {
    return SetAndroidAudioAttributesResponse.fromMap(await _channel
        .invokeMethod('setAndroidAudioAttributes', request?.toMap()));
  }

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    return DisposeResponse.fromMap(
        await _channel.invokeMethod('dispose', request?.toMap()));
  }

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
      ConcatenatingInsertAllRequest request) async {
    return ConcatenatingInsertAllResponse.fromMap(await _channel.invokeMethod(
        'concatenatingInsertAll', request?.toMap()));
  }

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
      ConcatenatingRemoveRangeRequest request) async {
    return ConcatenatingRemoveRangeResponse.fromMap(await _channel.invokeMethod(
        'concatenatingRemoveRange', request?.toMap()));
  }

  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(
      ConcatenatingMoveRequest request) async {
    return ConcatenatingMoveResponse.fromMap(
        await _channel.invokeMethod('concatenatingMove', request?.toMap()));
  }
}
