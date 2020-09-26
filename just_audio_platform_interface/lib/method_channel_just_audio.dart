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
}

class MethodChannelAudioPlayer extends AudioPlayerPlatform {
  final String id;
  final MethodChannel _channel;

  MethodChannelAudioPlayer(this.id)
      : _channel = MethodChannel('com.ryanheise.just_audio.methods.$id');

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    return (await _channel.invokeMethod('load', request?.toMap()))?.fromMap();
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    return (await _channel.invokeMethod('play', request?.toMap()))?.fromMap();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    return (await _channel.invokeMethod('pause', request?.toMap()))?.fromMap();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async {
    return (await _channel.invokeMethod('setVolume', request?.toMap()))
        ?.fromMap();
  }

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async {
    return (await _channel.invokeMethod('setSpeed', request?.toMap()))
        ?.fromMap();
  }

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async {
    return (await _channel.invokeMethod('setLoopMode', request?.toMap()))
        ?.fromMap();
  }

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
      SetShuffleModeRequest request) async {
    return (await _channel.invokeMethod('setShuffleMode', request?.toMap()))
        ?.fromMap();
  }

  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
      setAutomaticallyWaitsToMinimizeStalling(
          SetAutomaticallyWaitsToMinimizeStallingRequest request) async {
    return (await _channel.invokeMethod(
            'setAutomaticallyWaitsToMinimizeStalling', request?.toMap()))
        ?.fromMap();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    return (await _channel.invokeMethod('seek', request?.toMap()))?.fromMap();
  }

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
      SetAndroidAudioAttributesRequest request) async {
    return (await _channel.invokeMethod(
            'setAndroidAudioAttributes', request?.toMap()))
        ?.fromMap();
  }

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    return (await _channel.invokeMethod('dispose', request?.toMap()))
        ?.fromMap();
  }

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
      ConcatenatingInsertAllRequest request) async {
    return (await _channel.invokeMethod(
            'concatenatingInsertAll', request?.toMap()))
        ?.fromMap();
  }

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
      ConcatenatingRemoveRangeRequest request) async {
    return (await _channel.invokeMethod(
            'concatenatingRemoveRange', request?.toMap()))
        ?.fromMap();
  }

  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(
      ConcatenatingMoveRequest request) async {
    return (await _channel.invokeMethod('concatenatingMove', request?.toMap()))
        ?.fromMap();
  }
}
