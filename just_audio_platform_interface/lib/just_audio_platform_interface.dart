import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart' show required;
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

  /// Creates a new player and returns a nested platform interface for
  /// communicating with that player.
  Future<AudioPlayerPlatform> init(InitRequest request) {
    throw UnimplementedError('init() has not been implemented.');
  }
}

/// A nested platform interface for communicating with a particular player
/// instance.
abstract class AudioPlayerPlatform {
  Stream<PlaybackEventMessage> get playbackEventMessageStream;
  Future<LoadResponse> load(LoadRequest request);
  Future<PlayResponse> play(PlayRequest request);
  Future<PauseResponse> pause(PauseRequest request);
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request);
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request);
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request);
  Future<SetShuffleModeResponse> setShuffleMode(SetShuffleModeRequest request);
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
      setAutomaticallyWaitsToMinimizeStalling(
          SetAutomaticallyWaitsToMinimizeStallingRequest request);
  Future<SeekResponse> seek(SeekRequest request);
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
      SetAndroidAudioAttributesRequest request);
  Future<DisposeResponse> dispose(DisposeRequest request);
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
      ConcatenatingInsertAllRequest request);
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
      ConcatenatingRemoveRangeRequest request);
  Future<ConcatenatingMoveResponse> concatenatingMove(
      ConcatenatingMoveRequest request);
}

class PlaybackEventMessage {
  final ProcessingStateMessage processingState;
  final DateTime updateTime;
  final Duration updatePosition;
  final Duration bufferedPosition;
  final Duration duration;
  final IcyMetadataMessage icyMetadata;
  final int currentIndex;
  final int androidAudioSessionId;

  PlaybackEventMessage({
    @required this.processingState,
    @required this.updateTime,
    @required this.updatePosition,
    @required this.bufferedPosition,
    @required this.duration,
    @required this.icyMetadata,
    @required this.currentIndex,
    @required this.androidAudioSessionId,
  });

  static PlaybackEventMessage fromMap(Map<dynamic, dynamic> map) =>
      PlaybackEventMessage(
        processingState: ProcessingStateMessage.values[map['processingState']],
        updateTime: DateTime.fromMillisecondsSinceEpoch(map['updateTime']),
        // TODO: Ensure all platforms pass a microsecond value.
        updatePosition: Duration(microseconds: map['updatePosition']),
        // TODO: Ensure all platforms pass a microsecond value.
        bufferedPosition: Duration(microseconds: map['bufferedPosition']),
        // TODO: Ensure all platforms pass a microsecond value.
        duration: map['duration'] == null || map['duration'] < 0
            ? null
            : Duration(microseconds: map['duration']),
        icyMetadata: map['icyMetadata'] == null
            ? null
            : IcyMetadataMessage.fromMap(map['icyMetadata']),
        currentIndex: map['currentIndex'],
        androidAudioSessionId: map['androidAudioSessionId'],
      );
}

enum ProcessingStateMessage {
  none,
  loading,
  buffering,
  ready,
  completed,
}

class IcyMetadataMessage {
  final IcyInfoMessage info;
  final IcyHeadersMessage headers;

  IcyMetadataMessage({
    @required this.info,
    @required this.headers,
  });

  static IcyMetadataMessage fromMap(Map<dynamic, dynamic> json) =>
      IcyMetadataMessage(
        info:
            json['info'] == null ? null : IcyInfoMessage.fromMap(json['info']),
        headers: json['headers'] == null
            ? null
            : IcyHeadersMessage.fromMap(json['headers']),
      );
}

class IcyInfoMessage {
  final String title;
  final String url;

  IcyInfoMessage({@required this.title, @required this.url});

  static IcyInfoMessage fromMap(Map<dynamic, dynamic> json) =>
      IcyInfoMessage(title: json['title'], url: json['url']);
}

class IcyHeadersMessage {
  final int bitrate;
  final String genre;
  final String name;
  final int metadataInterval;
  final String url;
  final bool isPublic;

  IcyHeadersMessage({
    @required this.bitrate,
    @required this.genre,
    @required this.name,
    @required this.metadataInterval,
    @required this.url,
    @required this.isPublic,
  });

  static IcyHeadersMessage fromMap(Map<dynamic, dynamic> json) =>
      IcyHeadersMessage(
        bitrate: json['bitrate'],
        genre: json['genre'],
        name: json['name'],
        metadataInterval: json['metadataInterval'],
        url: json['url'],
        isPublic: json['isPublic'],
      );
}

class InitRequest {
  final String id;

  InitRequest({@required this.id});

  Map<dynamic, dynamic> toMap() => {
        'id': id,
      };
}

class LoadRequest {
  final AudioSourceMessage audioSourceMessage;

  LoadRequest({@required this.audioSourceMessage});

  Map<dynamic, dynamic> toMap() => {
        'audioSource': audioSourceMessage.toMap(),
      };
}

class LoadResponse {
  final Duration duration;

  LoadResponse({@required this.duration});

  static LoadResponse fromMap(Map<dynamic, dynamic> map) => LoadResponse(
      duration: map['duration'] != null
          ? Duration(microseconds: map['duration'])
          : null);
}

class PlayRequest {
  Map<dynamic, dynamic> toMap() => {};
}

class PlayResponse {
  static PlayResponse fromMap(Map<dynamic, dynamic> map) => PlayResponse();
}

class PauseRequest {
  Map<dynamic, dynamic> toMap() => {};
}

class PauseResponse {
  static PauseResponse fromMap(Map<dynamic, dynamic> map) => PauseResponse();
}

class SetVolumeRequest {
  final double volume;

  SetVolumeRequest({@required this.volume});

  Map<dynamic, dynamic> toMap() => {
        'volume': volume,
      };
}

class SetVolumeResponse {
  static SetVolumeResponse fromMap(Map<dynamic, dynamic> map) =>
      SetVolumeResponse();
}

class SetSpeedRequest {
  final double speed;

  SetSpeedRequest({@required this.speed});

  Map<dynamic, dynamic> toMap() => {
        'speed': speed,
      };
}

class SetSpeedResponse {
  static SetSpeedResponse fromMap(Map<dynamic, dynamic> map) =>
      SetSpeedResponse();
}

class SetLoopModeRequest {
  final LoopModeMessage loopMode;

  SetLoopModeRequest({@required this.loopMode});

  Map<dynamic, dynamic> toMap() => {
        'loopMode': describeEnum(loopMode),
      };
}

class SetLoopModeResponse {
  static SetLoopModeResponse fromMap(Map<dynamic, dynamic> map) =>
      SetLoopModeResponse();
}

enum LoopModeMessage { off, one, all }

class SetShuffleModeRequest {
  final ShuffleModeMessage shuffleMode;

  SetShuffleModeRequest({@required this.shuffleMode});

  Map<dynamic, dynamic> toMap() => {
        'shuffleMode': describeEnum(shuffleMode),
      };
}

class SetShuffleModeResponse {
  static SetShuffleModeResponse fromMap(Map<dynamic, dynamic> map) =>
      SetShuffleModeResponse();
}

enum ShuffleModeMessage { none, all }

class SetAutomaticallyWaitsToMinimizeStallingRequest {
  final bool enabled;

  SetAutomaticallyWaitsToMinimizeStallingRequest({@required this.enabled});

  Map<dynamic, dynamic> toMap() => {
        'enabled': enabled,
      };
}

class SetAutomaticallyWaitsToMinimizeStallingResponse {
  static SetAutomaticallyWaitsToMinimizeStallingResponse fromMap(
          Map<dynamic, dynamic> map) =>
      SetAutomaticallyWaitsToMinimizeStallingResponse();
}

class SeekRequest {
  final Duration position;
  final int index;

  SeekRequest({@required this.position, this.index});

  Map<dynamic, dynamic> toMap() => {
        'position': position.inMicroseconds,
        'index': index,
      };
}

class SeekResponse {
  static SeekResponse fromMap(Map<dynamic, dynamic> map) => SeekResponse();
}

class SetAndroidAudioAttributesRequest {
  final int contentType;
  final int flags;
  final int usage;

  SetAndroidAudioAttributesRequest({
    @required this.contentType,
    @required this.flags,
    @required this.usage,
  });

  Map<dynamic, dynamic> toMap() => {
        'contentType': contentType,
        'flags': flags,
        'usage': usage,
      };
}

class SetAndroidAudioAttributesResponse {
  static SetAndroidAudioAttributesResponse fromMap(Map<dynamic, dynamic> map) =>
      SetAndroidAudioAttributesResponse();
}

class DisposeRequest {
  Map<dynamic, dynamic> toMap() => {};
}

class DisposeResponse {
  static DisposeResponse fromMap(Map<dynamic, dynamic> map) =>
      DisposeResponse();
}

class ConcatenatingInsertAllRequest {
  final String id;
  final int index;
  final List<AudioSourceMessage> children;

  ConcatenatingInsertAllRequest({
    @required this.id,
    @required this.index,
    @required this.children,
  });

  Map<dynamic, dynamic> toMap() => {
        'id': id,
        'index': index,
        'children': children.map((child) => child.toMap()).toList(),
      };
}

class ConcatenatingInsertAllResponse {
  static ConcatenatingInsertAllResponse fromMap(Map<dynamic, dynamic> map) =>
      ConcatenatingInsertAllResponse();
}

class ConcatenatingRemoveRangeRequest {
  final String id;
  final int startIndex;
  final int endIndex;

  ConcatenatingRemoveRangeRequest({
    @required this.id,
    @required this.startIndex,
    @required this.endIndex,
  });

  Map<dynamic, dynamic> toMap() => {
        'id': id,
        'startIndex': startIndex,
        'endIndex': endIndex,
      };
}

class ConcatenatingRemoveRangeResponse {
  static ConcatenatingRemoveRangeResponse fromMap(Map<dynamic, dynamic> map) =>
      ConcatenatingRemoveRangeResponse();
}

class ConcatenatingMoveRequest {
  final String id;
  final int currentIndex;
  final int newIndex;

  ConcatenatingMoveRequest({
    @required this.id,
    @required this.currentIndex,
    @required this.newIndex,
  });

  Map<dynamic, dynamic> toMap() => {
        'id': id,
        'currentIndex': currentIndex,
        'newIndex': newIndex,
      };
}

class ConcatenatingMoveResponse {
  static ConcatenatingMoveResponse fromMap(Map<dynamic, dynamic> map) =>
      ConcatenatingMoveResponse();
}

abstract class AudioSourceMessage {
  final String id;

  AudioSourceMessage({@required this.id});

  Map<dynamic, dynamic> toMap();
}

abstract class IndexedAudioSourceMessage extends AudioSourceMessage {
  IndexedAudioSourceMessage({@required String id}) : super(id: id);
}

abstract class UriAudioSourceMessage extends IndexedAudioSourceMessage {
  final String uri;
  final Map<dynamic, dynamic> headers;

  UriAudioSourceMessage({
    @required String id,
    @required this.uri,
    @required this.headers,
  }) : super(id: id);
}

class ProgressiveAudioSourceMessage extends UriAudioSourceMessage {
  ProgressiveAudioSourceMessage({
    @required String id,
    @required String uri,
    @required Map<dynamic, dynamic> headers,
  }) : super(id: id, uri: uri, headers: headers);

  @override
  Map<dynamic, dynamic> toMap() => {
        'type': 'progressive',
        'id': id,
        'uri': uri,
        'headers': headers,
      };
}

class DashAudioSourceMessage extends UriAudioSourceMessage {
  DashAudioSourceMessage({
    @required String id,
    @required String uri,
    @required Map<dynamic, dynamic> headers,
  }) : super(id: id, uri: uri, headers: headers);

  @override
  Map<dynamic, dynamic> toMap() => {
        'type': 'dash',
        'id': id,
        'uri': uri,
        'headers': headers,
      };
}

class HlsAudioSourceMessage extends UriAudioSourceMessage {
  HlsAudioSourceMessage({
    @required String id,
    @required String uri,
    @required Map<dynamic, dynamic> headers,
  }) : super(id: id, uri: uri, headers: headers);

  @override
  Map<dynamic, dynamic> toMap() => {
        'type': 'hls',
        'id': id,
        'uri': uri,
        'headers': headers,
      };
}

class ConcatenatingAudioSourceMessage extends AudioSourceMessage {
  final List<AudioSourceMessage> children;
  final bool useLazyPreparation;

  ConcatenatingAudioSourceMessage({
    @required String id,
    @required this.children,
    @required this.useLazyPreparation,
  }) : super(id: id);

  @override
  Map<dynamic, dynamic> toMap() => {
        'type': 'concatenating',
        'id': id,
        // TODO: ensure platform implementation uses this key
        'children': children.map((child) => child.toMap()).toList(),
        'useLazyPreparation': useLazyPreparation,
      };
}

class ClippingAudioSourceMessage extends IndexedAudioSourceMessage {
  final UriAudioSourceMessage child;
  final Duration start;
  final Duration end;

  ClippingAudioSourceMessage({
    @required String id,
    @required this.child,
    @required this.start,
    @required this.end,
  }) : super(id: id);

  @override
  Map<dynamic, dynamic> toMap() => {
        'type': 'clipping',
        'id': id,
        // TODO: ensure platform implementation uses this key
        'child': child.toMap(),
        // TODO: ensure platform implementation interprets in Us.
        'start': start.inMicroseconds,
        // TODO: ensure platform implementation interprets in Us.
        'end': end.inMicroseconds,
      };
}

class LoopingAudioSourceMessage extends AudioSourceMessage {
  final AudioSourceMessage child;
  final int count;

  LoopingAudioSourceMessage({
    @required String id,
    @required this.child,
    @required this.count,
  }) : super(id: id);

  @override
  Map<dynamic, dynamic> toMap() => {
        'type': 'looping',
        'id': id,
        // TODO: ensure platform implementation uses this key
        'child': child.toMap(),
        'count': count,
      };
}
