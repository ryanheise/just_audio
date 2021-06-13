import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:rxdart/rxdart.dart';

late SwitchAudioHandler _audioHandler;
late JustAudioPlatform _platform;

class JustAudioBackgroundPlugin extends JustAudioPlatform {
  static Future<void> setup() async {
    _platform = JustAudioPlatform.instance;
    JustAudioPlatform.instance = JustAudioBackgroundPlugin();
    _audioHandler = await AudioService.init(
      builder: () => SwitchAudioHandler(BaseAudioHandler()),
      config: AudioServiceConfig(
        androidNotificationChannelName: 'Just Audio Demo',
        notificationColor: Color(0xFF2196f3),
        androidNotificationIcon: 'mipmap/ic_launcher',
        androidEnableQueue: true,
      ),
    );
  }

  JustAudioPlayer? _player;

  JustAudioBackgroundPlugin();

  @override
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

  @override
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
  bool? _playing;
  int? _index;
  Duration? _duration;
  IcyMetadataMessage? _icyMetadata;
  int? _androidAudioSessionId;
  late final PlayerAudioHandler _playerAudioHandler;

  JustAudioPlayer({required String id}) : super(id) {
    _playerAudioHandler = PlayerAudioHandler(id);
    _audioHandler.inner = _playerAudioHandler;
    _audioHandler.playbackState.listen((playbackState) {
      broadcastPlaybackEvent();
    });
    _audioHandler.customEvent.listen((event) {
      switch (event['type']) {
        case 'icyMetadata':
          _icyMetadata = event['value'];
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
    _audioHandler.mediaItem.listen((mediaItem) {
      if (mediaItem == null) return;
      _duration = mediaItem.duration;
    });
  }

  PlaybackState get playbackState => _audioHandler.playbackState.nvalue!;

  Future<void> release() async {
    eventController.close();
    await _audioHandler.stop();
  }

  Future<void> updateQueue(List<MediaItem> queue) async {
    await _audioHandler.updateQueue(queue);
  }

  broadcastPlaybackEvent() {
    if (eventController.isClosed) return;
    eventController.add(PlaybackEventMessage(
      //processingState: playbackState.processingState,
      processingState: {
        AudioProcessingState.idle: ProcessingStateMessage.idle,
        AudioProcessingState.loading: ProcessingStateMessage.loading,
        AudioProcessingState.ready: ProcessingStateMessage.ready,
        AudioProcessingState.buffering: ProcessingStateMessage.buffering,
        AudioProcessingState.completed: ProcessingStateMessage.completed,
        AudioProcessingState.error: ProcessingStateMessage.idle,
      }[playbackState.processingState]!,
      updatePosition: playbackState.position,
      updateTime: playbackState.updateTime,
      bufferedPosition: playbackState.bufferedPosition,
      icyMetadata: _icyMetadata,
      duration: _duration,
      currentIndex: _index,
      androidAudioSessionId: _androidAudioSessionId,
    ));
    if (playbackState.playing != _playing) {
      _playing = playbackState.playing;
      playerDataController.add(PlayerDataMessage(
        playing: playbackState.playing,
      ));
    }
  }

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      eventController.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream =>
      playerDataController.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    return _playerAudioHandler.customLoad(request);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    await _audioHandler.play();
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    await _audioHandler.pause();
    return PauseResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) =>
      _playerAudioHandler.customSetVolume(request);

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async {
    await _audioHandler.setSpeed(request.speed);
    return SetSpeedResponse();
  }

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async {
    await _audioHandler
        .setRepeatMode(AudioServiceRepeatMode.values[request.loopMode.index]);
    return SetLoopModeResponse();
  }

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
      SetShuffleModeRequest request) async {
    await _audioHandler.setShuffleMode(
        AudioServiceShuffleMode.values[request.shuffleMode.index]);
    return SetShuffleModeResponse();
  }

  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(
          SetShuffleOrderRequest request) =>
      _playerAudioHandler.customSetShuffleOrder(request);

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    return await _playerAudioHandler.customPlayerSeek(request);
  }

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
      ConcatenatingInsertAllRequest request) async {
    return _playerAudioHandler.customConcatenatingInsertAll(request);
  }

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
      ConcatenatingRemoveRangeRequest request) async {
    return await _playerAudioHandler.customConcatenatingRemoveRange(request);
  }

  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(
      ConcatenatingMoveRequest request) async {
    return await _playerAudioHandler.customConcatenatingMove(request);
  }

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
      SetAndroidAudioAttributesRequest request) async {
    return await _playerAudioHandler.customSetAndroidAudioAttributes(request);
  }

  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
      setAutomaticallyWaitsToMinimizeStalling(
          SetAutomaticallyWaitsToMinimizeStallingRequest request) async {
    return await _playerAudioHandler
        .customSetAutomaticallyWaitsToMinimizeStalling(request);
  }
}

class PlayerAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  Completer<AudioPlayerPlatform> _playerCompleter = Completer();
  PlaybackEventMessage _justAudioEvent = PlaybackEventMessage(
    processingState: ProcessingStateMessage.idle,
    updateTime: DateTime.now(),
    updatePosition: Duration.zero,
    bufferedPosition: Duration.zero,
    duration: null,
    icyMetadata: null,
    currentIndex: null,
    androidAudioSessionId: null,
  );
  AudioSourceMessage? _source;
  bool _playing = false;
  double _speed = 1.0;
  Seeker? _seeker;

  Future<AudioPlayerPlatform> get _player => _playerCompleter.future;
  int? get index => _justAudioEvent.currentIndex;
  MediaItem? get currentMediaItem => index != null &&
          currentQueue != null &&
          index! >= 0 &&
          index! < currentQueue!.length
      ? currentQueue![index!]
      : null;

  List<MediaItem>? get currentQueue => queue.nvalue;

  PlayerAudioHandler(String playerId) {
    _init(playerId);
  }

  Future<void> _init(String playerId) async {
    final player = await _platform.init(InitRequest(id: playerId));
    _playerCompleter.complete(player);
    final playbackEventMessageStream = player.playbackEventMessageStream;
    playbackEventMessageStream.listen((event) {
      _justAudioEvent = event;
      _broadcastState();
    });
    playbackEventMessageStream
        .map((event) => event.icyMetadata)
        .distinct()
        .listen((icyMetadata) {
      customEvent.add({
        'type': 'icyMetadata',
        'value': icyMetadata,
      });
    });
    playbackEventMessageStream
        .map((event) => event.androidAudioSessionId)
        .distinct()
        .listen((audioSessionId) {
      customEvent.add({
        'type': 'androidAudioSessionId',
        'value': audioSessionId,
      });
    });
    playbackEventMessageStream
        .map((event) => TrackInfo(event.currentIndex, event.duration))
        .distinct()
        .debounceTime(const Duration(milliseconds: 100))
        .listen((track) {
      final currentMediaItem = this.currentMediaItem;
      if (currentMediaItem != null) {
        if (track.duration != currentMediaItem.duration) {
          currentQueue![index!] = currentQueue![index!]
              .copyWith(duration: _justAudioEvent.duration);
          queue.add(currentQueue!);
        }
        mediaItem.add(this.currentMediaItem!);
      }
    });
    playbackEventMessageStream
        .map((event) => event.currentIndex)
        .distinct()
        .listen((index) {
      customEvent.add({
        'type': 'currentIndex',
        'value': index,
      });
    });
  }

  @override
  Future<void> updateQueue(List<MediaItem> queue) async {
    this.queue.add(queue);
    if (mediaItem.nvalue == null &&
        index != null &&
        index! >= 0 &&
        index! < queue.length) {
      mediaItem.add(queue[index!]);
    }
  }

  Future<LoadResponse> customLoad(LoadRequest request) async {
    _source = request.audioSourceMessage;
    _updateQueue();
    final response = await (await _player).load(LoadRequest(
      audioSourceMessage: _source!,
      initialPosition: request.initialPosition,
      initialIndex: request.initialIndex,
    ));
    return LoadResponse(duration: response.duration);
  }

  Future<SetVolumeResponse> customSetVolume(SetVolumeRequest request) async {
    return await (await _player).setVolume(request);
  }

  Future<SeekResponse> customPlayerSeek(SeekRequest request) async {
    return await (await _player).seek(request);
  }

  Future<SetShuffleOrderResponse> customSetShuffleOrder(
      SetShuffleOrderRequest request) async {
    _source = request.audioSourceMessage;
    return await (await _player).setShuffleOrder(SetShuffleOrderRequest(
      audioSourceMessage: _source!,
    ));
  }

  Future<ConcatenatingInsertAllResponse> customConcatenatingInsertAll(
      ConcatenatingInsertAllRequest request) async {
    final cat = _source!.findCat(request.id)!;
    cat.children.insertAll(request.index, request.children);
    _updateQueue();
    return await (await _player).concatenatingInsertAll(request);
  }

  Future<ConcatenatingRemoveRangeResponse> customConcatenatingRemoveRange(
      ConcatenatingRemoveRangeRequest request) async {
    final cat = _source!.findCat(request.id)!;
    cat.children.removeRange(request.startIndex, request.endIndex);
    _updateQueue();
    return await (await _player).concatenatingRemoveRange(request);
  }

  Future<ConcatenatingMoveResponse> customConcatenatingMove(
      ConcatenatingMoveRequest request) async {
    final cat = _source!.findCat(request.id)!;
    cat.children
        .insert(request.newIndex, cat.children.removeAt(request.currentIndex));
    _updateQueue();
    return await (await _player).concatenatingMove(request);
  }

  Future<SetAndroidAudioAttributesResponse> customSetAndroidAudioAttributes(
      SetAndroidAudioAttributesRequest request) async {
    return await (await _player).setAndroidAudioAttributes(request);
  }

  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
      customSetAutomaticallyWaitsToMinimizeStalling(
          SetAutomaticallyWaitsToMinimizeStallingRequest request) async {
    return await (await _player)
        .setAutomaticallyWaitsToMinimizeStalling(request);
  }

  Future<void> _updateQueue() async {
    queue.add(sequence.map((source) => source.tag as MediaItem).toList());
  }

  List<IndexedAudioSourceMessage> get sequence => _source!.sequence;

  @override
  Future<void> skipToQueueItem(int index) async {
    (await _player).seek(SeekRequest(position: Duration.zero, index: index));
  }

  @override
  Future<void> play() async {
    _updatePosition();
    _playing = true;
    _broadcastState();
    await (await _player).play(PlayRequest());
  }

  @override
  Future<void> pause() async {
    _updatePosition();
    _playing = false;
    _broadcastState();
    await (await _player).pause(PauseRequest());
  }

  void _updatePosition() {
    _justAudioEvent = _justAudioEvent.copyWith(
      updatePosition: currentPosition,
      updateTime: DateTime.now(),
    );
  }

  @override
  Future<void> seek(Duration position) async =>
      await (await _player).seek(SeekRequest(position: position));

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    await (await _player).setSpeed(SetSpeedRequest(speed: speed));
  }

  @override
  Future<void> fastForward() =>
      _seekRelative(AudioService.config.fastForwardInterval);

  @override
  Future<void> rewind() => _seekRelative(-AudioService.config.rewindInterval);

  @override
  Future<void> seekForward(bool begin) async => _seekContinuously(begin, 1);

  @override
  Future<void> seekBackward(bool begin) async => _seekContinuously(begin, -1);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    (await _player).setLoopMode(SetLoopModeRequest(
        loopMode: LoopModeMessage
            .values[min(LoopModeMessage.values.length - 1, repeatMode.index)]));
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    (await _player).setShuffleMode(SetShuffleModeRequest(
        shuffleMode: ShuffleModeMessage.values[
            min(ShuffleModeMessage.values.length - 1, shuffleMode.index)]));
  }

  @override
  Future<void> stop() async {
    await pause();
    _platform.disposePlayer(DisposePlayerRequest(id: (await _player).id));
    _justAudioEvent = _justAudioEvent.copyWith(
      processingState: ProcessingStateMessage.idle,
    );
    await _broadcastState();
    // Shut down this task
    await super.stop();
  }

  Duration get currentPosition {
    if (_playing &&
        _justAudioEvent.processingState == ProcessingStateMessage.ready) {
      return Duration(
          milliseconds: (_justAudioEvent.updatePosition.inMilliseconds +
                  ((DateTime.now().millisecondsSinceEpoch -
                          _justAudioEvent.updateTime.millisecondsSinceEpoch) *
                      _speed))
              .toInt());
    } else {
      return _justAudioEvent.updatePosition;
    }
  }

  /// Jumps away from the current position by [offset].
  Future<void> _seekRelative(Duration offset) async {
    var newPosition = currentPosition + offset;
    // Make sure we don't jump out of bounds.
    if (newPosition < Duration.zero) newPosition = Duration.zero;
    if (newPosition > currentMediaItem!.duration!)
      newPosition = currentMediaItem!.duration!;
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
          Duration(seconds: 1), currentMediaItem!.duration!)
        ..start();
    }
  }

  /// Broadcasts the current state to all clients.
  Future<void> _broadcastState() async {
    playbackState.add(playbackState.nvalue!.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (_playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: [0, 1, 3],
      processingState: {
        ProcessingStateMessage.idle: AudioProcessingState.idle,
        ProcessingStateMessage.loading: AudioProcessingState.loading,
        ProcessingStateMessage.buffering: AudioProcessingState.buffering,
        ProcessingStateMessage.ready: AudioProcessingState.ready,
        ProcessingStateMessage.completed: AudioProcessingState.completed,
      }[_justAudioEvent.processingState]!,
      playing: _playing,
      updatePosition: currentPosition,
      bufferedPosition: _justAudioEvent.bufferedPosition,
      speed: _speed,
      queueIndex: _justAudioEvent.currentIndex,
    ));
  }
}

class Seeker {
  final PlayerAudioHandler handler;
  final Duration positionInterval;
  final Duration stepInterval;
  final Duration duration;
  bool _running = false;

  Seeker(
    this.handler,
    this.positionInterval,
    this.stepInterval,
    this.duration,
  );

  start() async {
    _running = true;
    while (_running) {
      Duration newPosition = handler.currentPosition + positionInterval;
      if (newPosition < Duration.zero) newPosition = Duration.zero;
      if (newPosition > duration) newPosition = duration;
      handler.seek(newPosition);
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
      );
}

extension AudioSourceExtension on AudioSourceMessage {
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

/// Backwards compatible extensions on rxdart's ValueStream
extension _ValueStreamExtension<T> on ValueStream<T> {
  /// Backwards compatible version of valueOrNull.
  T? get nvalue => hasValue ? value : null;
}
