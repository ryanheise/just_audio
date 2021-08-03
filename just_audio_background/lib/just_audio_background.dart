import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:rxdart/rxdart.dart';

export 'package:audio_service/audio_service.dart' show MediaItem;

late SwitchAudioHandler _audioHandler;
late JustAudioPlatform _platform;

/// Provides the [init] method to initialise just_audio for background playback.
class JustAudioBackground {
  /// Initialise just_audio for background playback. This should be called from
  /// your app's `main` method. e.g.:
  ///
  /// ```dart
  /// Future<void> main() async {
  ///   await JustAudioBackground.init(
  ///     androidNotificationChannelId: 'com.ryanheise.bg_demo.channel.audio',
  ///     androidNotificationChannelName: 'Audio playback',
  ///     androidNotificationOngoing: true,
  ///   );
  ///   runApp(MyApp());
  /// }
  /// ```
  ///
  /// Each parameter controls a behaviour in audio_service. Consult
  /// audio_service's `AudioServiceConfig` API documentation for more
  /// information.
  static Future<void> init({
    bool androidResumeOnClick = true,
    String? androidNotificationChannelId,
    String androidNotificationChannelName = 'Notifications',
    String? androidNotificationChannelDescription,
    Color? notificationColor,
    String androidNotificationIcon = 'mipmap/ic_launcher',
    bool androidShowNotificationBadge = false,
    bool androidNotificationClickStartsActivity = true,
    bool androidNotificationOngoing = false,
    bool androidStopForegroundOnPause = true,
    int? artDownscaleWidth,
    int? artDownscaleHeight,
    Duration fastForwardInterval = const Duration(seconds: 10),
    Duration rewindInterval = const Duration(seconds: 10),
    bool preloadArtwork = false,
    Map<String, dynamic>? androidBrowsableRootExtras,
  }) async {
    WidgetsFlutterBinding.ensureInitialized();
    await _JustAudioBackgroundPlugin.setup(
      androidResumeOnClick: androidResumeOnClick,
      androidNotificationChannelId: androidNotificationChannelId,
      androidNotificationChannelName: androidNotificationChannelName,
      androidNotificationChannelDescription:
          androidNotificationChannelDescription,
      notificationColor: notificationColor,
      androidNotificationIcon: androidNotificationIcon,
      androidShowNotificationBadge: androidShowNotificationBadge,
      androidNotificationClickStartsActivity:
          androidNotificationClickStartsActivity,
      androidNotificationOngoing: androidNotificationOngoing,
      androidStopForegroundOnPause: androidStopForegroundOnPause,
      artDownscaleWidth: artDownscaleWidth,
      artDownscaleHeight: artDownscaleHeight,
      fastForwardInterval: fastForwardInterval,
      rewindInterval: rewindInterval,
      preloadArtwork: preloadArtwork,
      androidBrowsableRootExtras: androidBrowsableRootExtras,
    );
  }
}

class _JustAudioBackgroundPlugin extends JustAudioPlatform {
  static Future<void> setup({
    bool androidResumeOnClick = true,
    String? androidNotificationChannelId,
    String androidNotificationChannelName = 'Notifications',
    String? androidNotificationChannelDescription,
    Color? notificationColor,
    String androidNotificationIcon = 'mipmap/ic_launcher',
    bool androidShowNotificationBadge = false,
    bool androidNotificationClickStartsActivity = true,
    bool androidNotificationOngoing = false,
    bool androidStopForegroundOnPause = true,
    int? artDownscaleWidth,
    int? artDownscaleHeight,
    Duration fastForwardInterval = const Duration(seconds: 10),
    Duration rewindInterval = const Duration(seconds: 10),
    bool preloadArtwork = false,
    Map<String, dynamic>? androidBrowsableRootExtras,
  }) async {
    _platform = JustAudioPlatform.instance;
    JustAudioPlatform.instance = _JustAudioBackgroundPlugin();
    _audioHandler = await AudioService.init(
      builder: () => SwitchAudioHandler(BaseAudioHandler()),
      config: AudioServiceConfig(
        androidResumeOnClick: androidResumeOnClick,
        androidNotificationChannelId: androidNotificationChannelId,
        androidNotificationChannelName: androidNotificationChannelName,
        androidNotificationChannelDescription:
            androidNotificationChannelDescription,
        notificationColor: notificationColor,
        androidNotificationIcon: androidNotificationIcon,
        androidShowNotificationBadge: androidShowNotificationBadge,
        androidNotificationClickStartsActivity:
            androidNotificationClickStartsActivity,
        androidNotificationOngoing: androidNotificationOngoing,
        androidStopForegroundOnPause: androidStopForegroundOnPause,
        artDownscaleWidth: artDownscaleWidth,
        artDownscaleHeight: artDownscaleHeight,
        fastForwardInterval: fastForwardInterval,
        rewindInterval: rewindInterval,
        preloadArtwork: preloadArtwork,
        androidBrowsableRootExtras: androidBrowsableRootExtras,
      ),
    );
  }

  _JustAudioPlayer? _player;

  _JustAudioBackgroundPlugin();

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    if (_player != null) {
      throw PlatformException(
          code: "error",
          message:
              "just_audio_background supports only a single player instance");
    }
    _player = _JustAudioPlayer(
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

class _JustAudioPlayer extends AudioPlayerPlatform {
  final eventController = StreamController<PlaybackEventMessage>.broadcast();
  final playerDataController = StreamController<PlayerDataMessage>.broadcast();
  bool? _playing;
  int? _index;
  Duration? _duration;
  IcyMetadataMessage? _icyMetadata;
  int? _androidAudioSessionId;
  late final _PlayerAudioHandler _playerAudioHandler;

  _JustAudioPlayer({required String id}) : super(id) {
    _playerAudioHandler = _PlayerAudioHandler(id);
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
          // The event is broadcast in response to the next mediaItem update
          // which happens immediately after this.
          break;
      }
    });
    _audioHandler.mediaItem.listen((mediaItem) {
      if (mediaItem == null) return;
      _duration = mediaItem.duration;
      broadcastPlaybackEvent();
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

class _PlayerAudioHandler extends BaseAudioHandler
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
  _Seeker? _seeker;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;
  AudioServiceShuffleMode _shuffleMode = AudioServiceShuffleMode.none;

  Future<AudioPlayerPlatform> get _player => _playerCompleter.future;
  int? get index => _justAudioEvent.currentIndex;
  MediaItem? get currentMediaItem => index != null &&
          currentQueue != null &&
          index! >= 0 &&
          index! < currentQueue!.length
      ? currentQueue![index!]
      : null;

  List<MediaItem>? get currentQueue => queue.nvalue;

  _PlayerAudioHandler(String playerId) {
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
        customEvent.add({
          'type': 'currentIndex',
          'value': track.index,
        });
        mediaItem.add(this.currentMediaItem!);
      }
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
    _broadcastStateIfActive();
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

  List<IndexedAudioSourceMessage> get sequence => _source?.sequence ?? [];
  List<int> get shuffleIndices => _source?.shuffleIndices ?? [];
  List<int> get effectiveIndices => _shuffleMode != AudioServiceShuffleMode.none
      ? shuffleIndices
      : List.generate(sequence.length, (i) => i);
  List<int> get shuffleIndicesInv {
    final inv = List.filled(effectiveIndices.length, 0);
    for (var i = 0; i < effectiveIndices.length; i++) {
      inv[effectiveIndices[i]] = i;
    }
    return inv;
  }

  List<int> get effectiveIndicesInv =>
      _shuffleMode != AudioServiceShuffleMode.none
          ? shuffleIndicesInv
          : List.generate(sequence.length, (i) => i);
  int get nextIndex => getRelativeIndex(1);
  int get previousIndex => getRelativeIndex(-1);
  bool get hasNext => nextIndex != -1;
  bool get hasPrevious => previousIndex != -1;

  int getRelativeIndex(int offset) {
    if (_repeatMode == AudioServiceRepeatMode.one) return index!;
    final effectiveIndices = this.effectiveIndices;
    if (effectiveIndices.isEmpty) return -1;
    final effectiveIndicesInv = this.effectiveIndicesInv;
    if (index! >= effectiveIndicesInv.length) return -1;
    final invPos = effectiveIndicesInv[index!];
    var newInvPos = invPos + offset;
    if (newInvPos >= effectiveIndices.length || newInvPos < 0) {
      if (_repeatMode == AudioServiceRepeatMode.all) {
        newInvPos %= effectiveIndices.length;
      } else {
        return -1;
      }
    }
    final result = effectiveIndices[newInvPos];
    return result;
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    (await _player).seek(SeekRequest(position: Duration.zero, index: index));
  }

  @override
  Future<void> skipToNext() async {
    if (hasNext) {
      await skipToQueueItem(nextIndex);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (hasPrevious) {
      await skipToQueueItem(previousIndex);
    }
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
    _repeatMode = repeatMode;
    _broadcastStateIfActive();
    (await _player).setLoopMode(SetLoopModeRequest(
        loopMode: LoopModeMessage
            .values[min(LoopModeMessage.values.length - 1, repeatMode.index)]));
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _shuffleMode = shuffleMode;
    _broadcastStateIfActive();
    (await _player).setShuffleMode(SetShuffleModeRequest(
        shuffleMode: ShuffleModeMessage.values[
            min(ShuffleModeMessage.values.length - 1, shuffleMode.index)]));
  }

  @override
  Future<void> stop() async {
    _updatePosition();
    _playing = false;
    _broadcastState();
    _platform.disposePlayer(DisposePlayerRequest(id: (await _player).id));
    _justAudioEvent = _justAudioEvent.copyWith(
      processingState: ProcessingStateMessage.idle,
    );
    await _broadcastState();
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
      _seeker = _Seeker(this, Duration(seconds: 10 * direction),
          Duration(seconds: 1), currentMediaItem!.duration!)
        ..start();
    }
  }

  Future<void> _broadcastStateIfActive() async {
    if (_justAudioEvent.processingState != ProcessingStateMessage.idle) {
      _broadcastState();
    }
  }

  /// Broadcasts the current state to all clients.
  Future<void> _broadcastState() async {
    final controls = [
      if (hasPrevious) MediaControl.skipToPrevious,
      if (_playing) MediaControl.pause else MediaControl.play,
      MediaControl.stop,
      if (hasNext) MediaControl.skipToNext,
    ];
    playbackState.add(playbackState.nvalue!.copyWith(
      controls: controls,
      systemActions: {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: List.generate(controls.length, (i) => i)
          .where((i) => controls[i].action != MediaAction.stop)
          .toList(),
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

class _Seeker {
  final _PlayerAudioHandler handler;
  final Duration positionInterval;
  final Duration stepInterval;
  final Duration duration;
  bool _running = false;

  _Seeker(
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

extension _PlaybackEventMessageExtension on PlaybackEventMessage {
  PlaybackEventMessage copyWith({
    ProcessingStateMessage? processingState,
    DateTime? updateTime,
    Duration? updatePosition,
    Duration? bufferedPosition,
    Duration? duration,
    IcyMetadataMessage? icyMetadata,
    int? currentIndex,
    int? androidAudioSessionId,
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

  List<int> get shuffleIndices {
    final self = this;
    if (self is ConcatenatingAudioSourceMessage) {
      var offset = 0;
      final childIndicesList = <List<int>>[];
      for (var child in self.children) {
        final childIndices =
            child.shuffleIndices.map((i) => i + offset).toList();
        childIndicesList.add(childIndices);
        offset += childIndices.length;
      }
      final indices = <int>[];
      for (var index in self.shuffleOrder) {
        indices.addAll(childIndicesList[index]);
      }
      return indices;
    } else if (self is LoopingAudioSourceMessage) {
      // TODO: This should combine indices of the children, like ConcatenatingAudioSource.
      // Also should be fixed in the plugin frontend.
      return List.generate(self.count, (i) => i);
    } else {
      return [0];
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
