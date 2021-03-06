import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:rxdart/rxdart.dart';

class JustAudioBackgroundPlugin extends JustAudioPlatform {
  static void setup() {
    JustAudioPlatform.instance = /*_instance =*/ JustAudioBackgroundPlugin();
  }

  static Future<bool> get running async {
    return await AudioService.runningStream.first;
  }

  JustAudioPlayer? _player;

  JustAudioBackgroundPlugin();

  Future<AudioPlayerPlatform> init(InitRequest request) async {
    if (_player != null) {
      throw PlatformException(
          code: "error",
          message:
              "just_audio_background supports only a single player instance");
    }
    _player = JustAudioPlayer(
      id: request.id,
    );
    return _player!;
  }

  Future<DisposePlayerResponse> disposePlayer(
      DisposePlayerRequest request) async {
    await _player?.release();
    _player = null;
    return DisposePlayerResponse();
  }
}

class JustAudioPlayer extends AudioPlayerPlatform {
  final eventController = StreamController<PlaybackEventMessage>();
  final playerDataController = StreamController<PlayerDataMessage>();
  int? _index;
  Duration? _duration;
  IcyMetadataMessage? _icyMetadata;
  int? _androidAudioSessionId;

  Future<bool>? _startFuture;

  JustAudioPlayer({required String id}) : super(id) {
    _startFuture = _start();
    AudioService.playbackStateStream.listen((playbackState) {
      broadcastPlaybackEvent();
    });
    AudioService.customEventStream.listen((event) {
      switch (event['type']) {
        case 'icyMetadata':
          _icyMetadata = IcyMetadataMessage.fromMap(event['value']);
          broadcastPlaybackEvent();
          break;
        case 'androidAudioSessionId':
          _androidAudioSessionId = event['value'];
          broadcastPlaybackEvent();
          break;
        case 'currentIndex':
          _index = event['value'];
          broadcastPlaybackEvent();
          break;
      }
    });
    AudioService.currentMediaItemStream.listen((mediaItem) {
      if (mediaItem == null) return;
      _duration = mediaItem.duration;
    });
  }

  Future<bool> _start() async {
    final running = await AudioService.runningStream.first;
    if (running) {
      final map = await AudioService.customAction('getData');
      playerDataController.add(PlayerDataMessage(
        audioSource: _audioSourceMessageFromMap(map['audioSource']),
        volume: map['volume'],
        speed: map['speed'],
        loopMode: LoopModeMessage.values[map['repeatMode']],
        shuffleMode: ShuffleModeMessage.values[map['shuffleMode']],
      ));
      return true;
    }
    return await AudioService.start(
      backgroundTaskEntrypoint: _audioPlayerTaskEntrypoint,
      androidNotificationChannelName: 'Just Audio Demo',
      androidNotificationColor: 0xFF2196f3,
      androidNotificationIcon: 'mipmap/ic_launcher',
      androidEnableQueue: true,
      params: {'playerId': id},
    );
  }

  PlaybackState get playbackState => AudioService.playbackState;

  Future<void> release() async {
    eventController.close();
    AudioService.stop();
  }

  Future<void> updateQueue(List<MediaItem> queue) async {
    await _startFuture;
    await AudioService.updateQueue(queue);
  }

  broadcastPlaybackEvent() {
    if (eventController.isClosed) return;
    eventController.add(PlaybackEventMessage(
      //processingState: playbackState.processingState,
      processingState: {
        AudioProcessingState.none: ProcessingStateMessage.idle,
        AudioProcessingState.connecting: ProcessingStateMessage.loading,
        AudioProcessingState.ready: ProcessingStateMessage.ready,
        AudioProcessingState.buffering: ProcessingStateMessage.buffering,
        AudioProcessingState.fastForwarding: ProcessingStateMessage.buffering,
        AudioProcessingState.rewinding: ProcessingStateMessage.buffering,
        AudioProcessingState.skippingToPrevious:
            ProcessingStateMessage.buffering,
        AudioProcessingState.skippingToNext: ProcessingStateMessage.buffering,
        AudioProcessingState.skippingToQueueItem:
            ProcessingStateMessage.buffering,
        AudioProcessingState.completed: ProcessingStateMessage.completed,
        AudioProcessingState.stopped: ProcessingStateMessage.idle,
        AudioProcessingState.error: ProcessingStateMessage.idle,
      }[playbackState.processingState]!,
      updatePosition: playbackState.position,
      updateTime: playbackState.updateTime,
      bufferedPosition: playbackState.bufferedPosition,
      icyMetadata: _icyMetadata,
      duration: _duration,
      currentIndex: _index,
      androidAudioSessionId: _androidAudioSessionId,
      playing: playbackState.playing,
    ));
  }

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      eventController.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream =>
      playerDataController.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    await _startFuture;
    final map = await AudioService.customAction('load', {
      'audioSource': request.audioSourceMessage.toMap2(),
      'initialPosition': request.initialPosition?.inMicroseconds,
      'initialIndex': request.initialIndex,
    });
    return LoadResponse(
        duration: map['duration'] != null
            ? Duration(microseconds: map['duration'])
            : null);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    await _startFuture;
    await AudioService.play();
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    await _startFuture;
    await AudioService.pause();
    return PauseResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async {
    await _startFuture;
    await AudioService.customAction('setVolume', request.toMap());
    return SetVolumeResponse();
  }

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async {
    await _startFuture;
    await AudioService.setSpeed(request.speed);
    return SetSpeedResponse();
  }

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async {
    await _startFuture;
    await AudioService.setRepeatMode(
        AudioServiceRepeatMode.values[request.loopMode.index]);
    return SetLoopModeResponse();
  }

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
      SetShuffleModeRequest request) async {
    await _startFuture;
    await AudioService.setShuffleMode(
        AudioServiceShuffleMode.values[request.shuffleMode.index]);
    return SetShuffleModeResponse();
  }

  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(
      SetShuffleOrderRequest request) async {
    await _startFuture;
    await AudioService.customAction('setShuffleOrder', request.toMap());
    return SetShuffleOrderResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    await _startFuture;
    await AudioService.customAction('seek', request.toMap());
    return SeekResponse();
  }

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
      ConcatenatingInsertAllRequest request) async {
    await _startFuture;
    await AudioService.customAction('concatenatingInsertAll', {
      'id': request.id,
      'index': request.index,
      'children': request.children.map((child) => child.toMap2()).toList(),
      'shuffleOrder': request.shuffleOrder,
    });
    return ConcatenatingInsertAllResponse();
  }

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
      ConcatenatingRemoveRangeRequest request) async {
    await _startFuture;
    await AudioService.customAction(
        'concatenatingRemoveRange', request.toMap());
    return ConcatenatingRemoveRangeResponse();
  }

  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(
      ConcatenatingMoveRequest request) async {
    await _startFuture;
    await AudioService.customAction('concatenatingMove', request.toMap());
    return ConcatenatingMoveResponse();
  }

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
      SetAndroidAudioAttributesRequest request) async {
    await _startFuture;
    await AudioService.customAction(
        'setAndroidAudioAttributes', request.toMap());
    return SetAndroidAudioAttributesResponse();
  }

  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
      setAutomaticallyWaitsToMinimizeStalling(
          SetAutomaticallyWaitsToMinimizeStallingRequest request) async {
    await _startFuture;
    await AudioService.customAction(
        'setAutomaticallyWaitsToMinimizeStalling', request.toMap());
    return SetAutomaticallyWaitsToMinimizeStallingResponse();
  }
}

void _audioPlayerTaskEntrypoint() async {
  AudioServiceBackground.run(() => AudioPlayerTask());
}

class AudioPlayerTask extends BackgroundAudioTask {
  Completer<AudioPlayerPlatform> _playerCompleter = Completer();
  AudioProcessingState? _skipState;
  PlaybackEventMessage _event = PlaybackEventMessage(
    processingState: ProcessingStateMessage.idle,
    updateTime: DateTime.now(),
    updatePosition: Duration.zero,
    bufferedPosition: Duration.zero,
    duration: null,
    icyMetadata: null,
    currentIndex: null,
    androidAudioSessionId: null,
    playing: false,
  );
  AudioSourceMessage? _source;
  bool _playing = false;
  double _speed = 1.0;
  double _volume = 1.0;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;
  AudioServiceShuffleMode _shuffleMode = AudioServiceShuffleMode.none;
  Seeker? _seeker;

  Future<AudioPlayerPlatform> get _player => _playerCompleter.future;
  int? get index => _event.currentIndex;
  MediaItem? get mediaItem =>
      index != null && queue != null && index! >= 0 && index! < queue!.length
          ? queue![index!]
          : null;

  List<MediaItem>? get queue => AudioServiceBackground.queue;

  @override
  Future<void> onStart(Map<String, dynamic>? params) async {
    final player = await JustAudioPlatform.instance
        .init(InitRequest(id: params!['playerId']));
    _playerCompleter.complete(player);
    final playbackEventMessageStream = player.playbackEventMessageStream;
    playbackEventMessageStream.listen((event) {
      _event = event;
      _broadcastState();
    });
    playbackEventMessageStream
        .map((event) => event.icyMetadata)
        .distinct()
        .listen((icyMetadata) {
      AudioServiceBackground.sendCustomEvent({
        'type': 'icyMetadata',
        'value': _encodeIcyMetadata(icyMetadata),
      });
    });
    playbackEventMessageStream
        .map((event) => event.androidAudioSessionId)
        .distinct()
        .listen((audioSessionId) {
      AudioServiceBackground.sendCustomEvent({
        'type': 'androidAudioSessionId',
        'value': audioSessionId,
      });
    });
    playbackEventMessageStream
        .map((event) => TrackInfo(event.currentIndex, event.duration))
        .distinct()
        .debounceTime(const Duration(milliseconds: 100))
        .listen((track) {
      final mediaItem = this.mediaItem;
      if (mediaItem != null) {
        if (track.duration != mediaItem.duration) {
          queue![index!] = queue![index!].copyWith(duration: _event.duration);
          AudioServiceBackground.setQueue(queue!);
        }
        AudioServiceBackground.setMediaItem(this.mediaItem!);
      }
    });
    playbackEventMessageStream
        .map((event) => event.currentIndex)
        .distinct()
        .listen((index) {
      AudioServiceBackground.sendCustomEvent({
        'type': 'currentIndex',
        'value': index,
      });
    });
    playbackEventMessageStream
        .map((event) => event.processingState)
        .where((state) => state == ProcessingStateMessage.ready)
        .listen((state) => _skipState = null);
  }

  @override
  Future<void> onUpdateQueue(List<MediaItem> queue) async {
    await AudioServiceBackground.setQueue(queue);
    if (AudioServiceBackground.mediaItem == null &&
        index != null &&
        index! >= 0 &&
        index! < queue.length) {
      AudioServiceBackground.setMediaItem(queue[index!]);
    }
  }

  Map? _encodeIcyMetadata(IcyMetadataMessage? icyMetadata) =>
      icyMetadata == null
          ? null
          : {
              'info': _encodeIcyInfo(icyMetadata.info),
              'headers': _encodeIcyHeaders(icyMetadata.headers),
            };

  Map? _encodeIcyInfo(IcyInfoMessage? icyInfo) => icyInfo == null
      ? null
      : {
          'title': icyInfo.title,
          'url': icyInfo.url,
        };

  Map? _encodeIcyHeaders(IcyHeadersMessage? icyHeaders) => icyHeaders == null
      ? null
      : {
          'bitrate': icyHeaders.bitrate,
          'genre': icyHeaders.genre,
          'name': icyHeaders.name,
          'metadataInterval': icyHeaders.metadataInterval,
          'url': icyHeaders.url,
          'isPublic': icyHeaders.isPublic,
        };

  @override
  Future<dynamic> onCustomAction(String name, dynamic arguments) async {
    try {
      switch (name) {
        case 'getData':
          AudioServiceBackground.sendCustomEvent({
            'type': 'currentIndex',
            'value': index,
          });
          if (_event.androidAudioSessionId != null) {
            AudioServiceBackground.sendCustomEvent({
              'type': 'androidAudioSessionId',
              'value': _event.androidAudioSessionId,
            });
          }
          if (_event.icyMetadata != null) {
            AudioServiceBackground.sendCustomEvent({
              'type': 'icyMetadata',
              'value': _encodeIcyMetadata(_event.icyMetadata),
            });
          }
          return {
            'audioSource': _source!.toMap2(),
            'volume': _volume,
            'speed': _speed,
            'repeatMode': _repeatMode.index,
            'shuffleMode': _shuffleMode.index,
          };
        case 'setVolume':
          _volume = arguments['volume'];
          await (await _player).setVolume(SetVolumeRequest(volume: _volume));
          break;
        case 'load':
          _source = _decodeAudioSource(arguments['audioSource']);
          _updateQueue();
          final response = await (await _player).load(LoadRequest(
            audioSourceMessage: _source!,
            initialPosition: arguments['initialPosition'] != null
                ? Duration(microseconds: arguments['initialPosition'])
                : null,
            initialIndex: arguments['initialIndex'],
          ));
          return {
            'duration': response.duration?.inMicroseconds,
          };
        case 'seek':
          await (await _player).seek(SeekRequest(
            position: Duration(microseconds: arguments['position']),
            index: arguments['index'],
          ));
          break;
        case 'setShuffleOrder':
          _source = _decodeAudioSource(arguments['audioSource']);
          await (await _player).setShuffleOrder(SetShuffleOrderRequest(
            audioSourceMessage: _source!,
          ));
          break;
        case 'concatenatingInsertAll':
          final children = (arguments['children'] as List)
              .cast<Map>()
              .map<AudioSourceMessage>(_decodeAudioSource)
              .toList();
          final request = ConcatenatingInsertAllRequest(
            id: arguments['id'],
            index: arguments['index'],
            children: children,
            shuffleOrder: arguments['shuffleOrder'].cast<int>(),
          );
          final cat = _source!.findCat(request.id)!;
          cat.children.insertAll(request.index, request.children);
          _updateQueue();
          await (await _player).concatenatingInsertAll(request);
          break;
        case 'concatenatingRemoveRange':
          final request = ConcatenatingRemoveRangeRequest(
            id: arguments['id'],
            startIndex: arguments['startIndex'],
            endIndex: arguments['endIndex'],
            shuffleOrder: arguments['shuffleOrder'].cast<int>(),
          );
          final cat = _source!.findCat(request.id)!;
          cat.children.removeRange(request.startIndex, request.endIndex);
          _updateQueue();
          await (await _player).concatenatingRemoveRange(request);
          break;
        case 'concatenatingMove':
          final request = ConcatenatingMoveRequest(
            id: arguments['id'],
            currentIndex: arguments['currentIndex'],
            newIndex: arguments['newIndex'],
            shuffleOrder: arguments['shuffleOrder'].cast<int>(),
          );
          final cat = _source!.findCat(request.id)!;
          cat.children.insert(
              request.newIndex, cat.children.removeAt(request.currentIndex));
          _updateQueue();
          await (await _player).concatenatingMove(request);
          break;
        case 'setAndroidAudioAttributes':
          await (await _player)
              .setAndroidAudioAttributes(SetAndroidAudioAttributesRequest(
            contentType: arguments['contentType'],
            flags: arguments['flags'],
            usage: arguments['usage'],
          ));
          break;
        case 'setAutomaticallyWaitsToMinimizeStalling':
          await (await _player).setAutomaticallyWaitsToMinimizeStalling(
              SetAutomaticallyWaitsToMinimizeStallingRequest(
            enabled: arguments['enabled'],
          ));
          break;
      }
    } catch (e, stackTrace) {
      print(e);
      print(stackTrace);
    }
  }

  Future<void> _updateQueue() async {
    await AudioServiceBackground.setQueue(
        sequence.map((source) => source.tag as MediaItem).toList());
  }

  List<IndexedAudioSourceMessage> get sequence => _source!.sequence;

  AudioSourceMessage _decodeAudioSource(Map map) {
    switch (map['type']) {
      case 'progressive':
        return ProgressiveAudioSourceMessage(
          id: map['id'],
          uri: map['uri'],
          headers: map['headers'],
          tag: map['tag'] == null ? null : MediaItem.fromJson(map['tag']),
        );
      case 'dash':
        return DashAudioSourceMessage(
          id: map['id'],
          uri: map['uri'],
          headers: map['headers'],
          tag: map['tag'] == null ? null : MediaItem.fromJson(map['tag']),
        );
      case 'hls':
        return HlsAudioSourceMessage(
          id: map['id'],
          uri: map['uri'],
          headers: map['headers'],
          tag: map['tag'] == null ? null : MediaItem.fromJson(map['tag']),
        );
      case 'concatenating':
        return ConcatenatingAudioSourceMessage(
          id: map['id'],
          children: (map['children'] as List)
              .cast<Map>()
              .map<AudioSourceMessage>(_decodeAudioSource)
              .toList(),
          useLazyPreparation: map['useLazyPreparation'],
          shuffleOrder: map['shuffleOrder'].cast<int>(),
        );
      case 'clipping':
        return ClippingAudioSourceMessage(
          id: map['id'],
          child: _decodeAudioSource(map['child']) as UriAudioSourceMessage,
          start: Duration(microseconds: map['start']),
          end: Duration(microseconds: map['end']),
          tag: map['tag'] == null ? null : MediaItem.fromJson(map['tag']),
        );
      case 'looping':
        return LoopingAudioSourceMessage(
          id: map['id'],
          child: _decodeAudioSource(map['child']),
          count: map['count'],
        );
      default:
        throw Exception("Unknown AudioSource type: ${map['type']}");
    }
  }

  @override
  Future<void> onSkipToQueueItem(String mediaId) async {
    final newIndex = queue!.indexWhere((item) => item.id == mediaId);
    if (newIndex == -1) return;
    _skipState = newIndex > index!
        ? AudioProcessingState.skippingToNext
        : AudioProcessingState.skippingToPrevious;
    (await _player).seek(SeekRequest(position: Duration.zero, index: newIndex));
  }

  @override
  Future<void> onPlay() async {
    _updatePosition();
    _playing = true;
    _broadcastState();
    await (await _player).play(PlayRequest());
  }

  @override
  Future<void> onPause() async {
    _updatePosition();
    _playing = false;
    _broadcastState();
    await (await _player).pause(PauseRequest());
  }

  void _updatePosition() {
    _event = _event.copyWith(
      updatePosition: currentPosition,
      updateTime: DateTime.now(),
    );
  }

  @override
  Future<void> onSeekTo(Duration position) async =>
      await (await _player).seek(SeekRequest(position: position));

  @override
  Future<void> onSetSpeed(double speed) async {
    _speed = speed;
    await (await _player).setSpeed(SetSpeedRequest(speed: speed));
  }

  @override
  Future<void> onFastForward() => _seekRelative(fastForwardInterval);

  @override
  Future<void> onRewind() => _seekRelative(-rewindInterval);

  @override
  Future<void> onSeekForward(bool begin) async => _seekContinuously(begin, 1);

  @override
  Future<void> onSeekBackward(bool begin) async => _seekContinuously(begin, -1);

  @override
  Future<void> onSetRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _repeatMode = repeatMode;
    (await _player).setLoopMode(SetLoopModeRequest(
        loopMode: LoopModeMessage
            .values[min(LoopModeMessage.values.length - 1, repeatMode.index)]));
  }

  @override
  Future<void> onSetShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _shuffleMode = shuffleMode;
    (await _player).setShuffleMode(SetShuffleModeRequest(
        shuffleMode: ShuffleModeMessage.values[
            min(ShuffleModeMessage.values.length - 1, shuffleMode.index)]));
  }

  @override
  Future<void> onStop() async {
    await onPause();
    (JustAudioPlatform.instance)
        .disposePlayer(DisposePlayerRequest(id: (await _player).id));
    _event = _event.copyWith(
      processingState: ProcessingStateMessage.idle,
    );
    await _broadcastState();
    // Shut down this task
    await super.onStop();
  }

  Duration get currentPosition {
    if (_playing && _event.processingState == ProcessingStateMessage.ready) {
      return Duration(
          milliseconds: (_event.updatePosition.inMilliseconds +
                  ((DateTime.now().millisecondsSinceEpoch -
                          _event.updateTime.millisecondsSinceEpoch) *
                      _speed))
              .toInt());
    } else {
      return _event.updatePosition;
    }
  }

  /// Jumps away from the current position by [offset].
  Future<void> _seekRelative(Duration offset) async {
    var newPosition = currentPosition + offset;
    // Make sure we don't jump out of bounds.
    if (newPosition < Duration.zero) newPosition = Duration.zero;
    if (newPosition > mediaItem!.duration!) newPosition = mediaItem!.duration!;
    // Perform the jump via a seek.
    await (await _player).seek(SeekRequest(position: newPosition));
  }

  /// Begins or stops a continuous seek in [direction]. After it begins it will
  /// continue seeking forward or backward by 10 seconds within the audio, at
  /// intervals of 1 second in app time.
  void _seekContinuously(bool begin, int direction) {
    _seeker?.stop();
    if (begin) {
      _seeker = Seeker(this, Duration(seconds: 10 * direction),
          Duration(seconds: 1), mediaItem!.duration!)
        ..start();
    }
  }

  /// Broadcasts the current state to all clients.
  Future<void> _broadcastState() async {
    await AudioServiceBackground.setState(
      controls: [
        MediaControl.skipToPrevious,
        if (_playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: [
        MediaAction.seekTo,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      ],
      androidCompactActions: [0, 1, 3],
      processingState: _skipState ??
          {
            ProcessingStateMessage.idle: AudioProcessingState.stopped,
            ProcessingStateMessage.loading: AudioProcessingState.connecting,
            ProcessingStateMessage.buffering: AudioProcessingState.buffering,
            ProcessingStateMessage.ready: AudioProcessingState.ready,
            ProcessingStateMessage.completed: AudioProcessingState.completed,
          }[_event.processingState],
      playing: _playing,
      position: currentPosition,
      bufferedPosition: _event.bufferedPosition,
      speed: _speed,
    );
  }
}

class Seeker {
  final AudioPlayerTask task;
  final Duration positionInterval;
  final Duration stepInterval;
  final Duration duration;
  bool _running = false;

  Seeker(
    this.task,
    this.positionInterval,
    this.stepInterval,
    this.duration,
  );

  start() async {
    _running = true;
    while (_running) {
      Duration newPosition = task.currentPosition + positionInterval;
      if (newPosition < Duration.zero) newPosition = Duration.zero;
      if (newPosition > duration) newPosition = duration;
      task.onSeekTo(newPosition);
      await Future.delayed(stepInterval);
    }
  }

  stop() {
    _running = false;
  }
}

extension PlaybackEventMessageExtension on PlaybackEventMessage {
  PlaybackEventMessage copyWith({
    ProcessingStateMessage? processingState,
    DateTime? updateTime,
    Duration? updatePosition,
    Duration? bufferedPosition,
    Duration? duration,
    IcyMetadataMessage? icyMetadata,
    int? currentIndex,
    int? androidAudioSessionId,
    bool? playing,
  }) =>
      PlaybackEventMessage(
        processingState: processingState ?? this.processingState,
        updateTime: updateTime ?? this.updateTime,
        updatePosition: updatePosition ?? this.updatePosition,
        bufferedPosition: bufferedPosition ?? this.bufferedPosition,
        duration: duration ?? this.duration,
        icyMetadata: icyMetadata ?? this.icyMetadata,
        currentIndex: currentIndex ?? this.currentIndex,
        androidAudioSessionId:
            androidAudioSessionId ?? this.androidAudioSessionId,
        playing: playing ?? this.playing,
      );
}

AudioSourceMessage _audioSourceMessageFromMap(Map<dynamic, dynamic> map) {
  final tag = map['tag'] != null ? MediaItem.fromJson(map['tag']) : null;
  switch (map['type']) {
    case 'progressive':
      return ProgressiveAudioSourceMessage(
        id: map['id'],
        uri: map['uri'],
        headers: map['headers'],
        tag: tag,
      );
    case 'dash':
      return DashAudioSourceMessage(
        id: map['id'],
        uri: map['uri'],
        headers: map['headers'],
        tag: tag,
      );
    case 'hls':
      return HlsAudioSourceMessage(
        id: map['id'],
        uri: map['uri'],
        headers: map['headers'],
        tag: tag,
      );
    case 'concatenating':
      final children = (map['children'] as List)
          .cast<Map>()
          .map<AudioSourceMessage>(_audioSourceMessageFromMap)
          .toList();
      return ConcatenatingAudioSourceMessage(
        id: map['id'],
        children: children,
        useLazyPreparation: map['useLazyPreparation'],
        shuffleOrder: map['shuffleOrder'].cast<int>(),
      );
    case 'clipping':
      return ClippingAudioSourceMessage(
        id: map['id'],
        child:
            _audioSourceMessageFromMap(map['child']) as UriAudioSourceMessage,
        start: Duration(microseconds: map['start']),
        end: Duration(microseconds: map['end']),
        tag: tag,
      );
    case 'looping':
      return LoopingAudioSourceMessage(
        id: map['id'],
        child: _audioSourceMessageFromMap(map['child']),
        count: map['count'],
      );
    default:
      throw Exception('Invalid audio source type: ${map['type']}');
  }
}

extension AudioSourceExtension on AudioSourceMessage {
  Map<dynamic, dynamic> toMap2() {
    final self = this;
    if (self is ConcatenatingAudioSourceMessage) {
      return {
        'type': 'concatenating',
        'id': self.id,
        'children': self.children.map((child) => child.toMap2()).toList(),
        'useLazyPreparation': self.useLazyPreparation,
        'shuffleOrder': self.shuffleOrder,
      };
    } else if (self is ClippingAudioSourceMessage) {
      return {
        'type': 'clipping',
        'id': self.id,
        'child': self.child.toMap2(),
        'start': self.start?.inMicroseconds,
        'end': self.end?.inMicroseconds,
        'tag': (self.tag as MediaItem).toJson(),
      };
    } else if (self is LoopingAudioSourceMessage) {
      return {
        'type': 'looping',
        'id': self.id,
        'child': self.child.toMap2(),
        'count': self.count,
      };
    } else if (self is IndexedAudioSourceMessage) {
      final map = toMap();
      map['tag'] = (self.tag as MediaItem?)?.toJson();
      return map;
    } else {
      throw Exception('Unsupported audio source message');
    }
  }

  ConcatenatingAudioSourceMessage? findCat(String id) {
    final self = this;
    if (self is ConcatenatingAudioSourceMessage) {
      if (self.id == id) return self;
      return self.children
          .map((child) => child.findCat(id))
          .firstWhere((cat) => cat != null, orElse: () => null);
    } else if (self is LoopingAudioSourceMessage) {
      return self.child.findCat(id);
    } else {
      return null;
    }
  }

  List<IndexedAudioSourceMessage> get sequence {
    final self = this;
    if (self is ConcatenatingAudioSourceMessage) {
      return self.children.expand((child) => child.sequence).toList();
    } else if (self is LoopingAudioSourceMessage) {
      return List.generate(self.count, (i) => self.child.sequence)
          .expand((sequence) => sequence)
          .toList();
    } else {
      return [self as IndexedAudioSourceMessage];
    }
  }
}

class TrackInfo {
  final int? index;
  final Duration? duration;

  const TrackInfo(this.index, this.duration);

  @override
  bool operator ==(Object other) =>
      other is TrackInfo && index == other.index && duration == other.duration;

  @override
  int get hashCode => "$index,$duration".hashCode;

  @override
  String toString() => '($index, $duration)';
}
