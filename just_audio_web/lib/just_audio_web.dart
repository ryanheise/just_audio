import 'dart:async';
import 'dart:html';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

final Random _random = Random();

class JustAudioPlugin extends JustAudioPlatform {
  final Map<String, JustAudioPlayer> players = {};

  static void registerWith(Registrar registrar) {
    JustAudioPlatform.instance = JustAudioPlugin();
  }

  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final player = Html5AudioPlayer(id: request.id);
    players[request.id] = player;
    return player;
  }

  Future<DisposePlayerResponse> disposePlayer(
      DisposePlayerRequest request) async {
    await players[request.id]?.release();
    return DisposePlayerResponse();
  }
}

abstract class JustAudioPlayer extends AudioPlayerPlatform {
  final eventController = StreamController<PlaybackEventMessage>();
  ProcessingStateMessage _processingState = ProcessingStateMessage.none;
  bool _playing = false;
  int _index;

  JustAudioPlayer({@required String id}) : super(id);

  @mustCallSuper
  Future<void> release() async {
    eventController.close();
  }

  Duration getCurrentPosition();

  Duration getBufferedPosition();

  Duration getDuration();

  broadcastPlaybackEvent() {
    var updateTime = DateTime.now();
    eventController.add(PlaybackEventMessage(
      processingState: _processingState,
      updatePosition: getCurrentPosition(),
      updateTime: updateTime,
      bufferedPosition: getBufferedPosition(),
      // TODO: Icy Metadata
      icyMetadata: null,
      duration: getDuration(),
      currentIndex: _index,
      androidAudioSessionId: null,
    ));
  }

  transition(ProcessingStateMessage processingState) {
    _processingState = processingState;
    broadcastPlaybackEvent();
  }
}

class Html5AudioPlayer extends JustAudioPlayer {
  AudioElement _audioElement = AudioElement();
  Completer _durationCompleter;
  AudioSourcePlayer _audioSourcePlayer;
  LoopModeMessage _loopMode = LoopModeMessage.off;
  bool _shuffleModeEnabled = false;
  final Map<String, AudioSourcePlayer> _audioSourcePlayers = {};

  Html5AudioPlayer({@required String id}) : super(id: id) {
    _audioElement.addEventListener('durationchange', (event) {
      _durationCompleter?.complete();
      broadcastPlaybackEvent();
    });
    _audioElement.addEventListener('error', (event) {
      _durationCompleter?.completeError(_audioElement.error);
    });
    _audioElement.addEventListener('ended', (event) async {
      _currentAudioSourcePlayer.complete();
    });
    _audioElement.addEventListener('timeupdate', (event) {
      _currentAudioSourcePlayer.timeUpdated(_audioElement.currentTime);
    });
    _audioElement.addEventListener('loadstart', (event) {
      transition(ProcessingStateMessage.buffering);
    });
    _audioElement.addEventListener('waiting', (event) {
      transition(ProcessingStateMessage.buffering);
    });
    _audioElement.addEventListener('stalled', (event) {
      transition(ProcessingStateMessage.buffering);
    });
    _audioElement.addEventListener('canplaythrough', (event) {
      transition(ProcessingStateMessage.ready);
    });
    _audioElement.addEventListener('progress', (event) {
      broadcastPlaybackEvent();
    });
  }

  List<int> get order {
    final sequence = _audioSourcePlayer.sequence;
    List<int> order = List<int>(sequence.length);
    if (_shuffleModeEnabled) {
      order = _audioSourcePlayer.shuffleIndices;
    } else {
      for (var i = 0; i < order.length; i++) {
        order[i] = i;
      }
    }
    return order;
  }

  List<int> getInv(List<int> order) {
    List<int> orderInv = List<int>(order.length);
    for (var i = 0; i < order.length; i++) {
      orderInv[order[i]] = i;
    }
    return orderInv;
  }

  onEnded() async {
    if (_loopMode == LoopModeMessage.one) {
      await _seek(0, null);
      _play();
    } else {
      final order = this.order;
      final orderInv = getInv(order);
      if (orderInv[_index] + 1 < order.length) {
        // move to next item
        _index = order[orderInv[_index] + 1];
        await _currentAudioSourcePlayer.load();
        // Should always be true...
        if (_playing) {
          _play();
        }
      } else {
        // reached end of playlist
        if (_loopMode == LoopModeMessage.all) {
          // Loop back to the beginning
          if (order.length == 1) {
            await _seek(0, null);
            _play();
          } else {
            _index = order[0];
            await _currentAudioSourcePlayer.load();
            // Should always be true...
            if (_playing) {
              _play();
            }
          }
        } else {
          transition(ProcessingStateMessage.completed);
        }
      }
    }
  }

  // TODO: Improve efficiency.
  IndexedAudioSourcePlayer get _currentAudioSourcePlayer =>
      _audioSourcePlayer != null && _index < _audioSourcePlayer.sequence.length
          ? _audioSourcePlayer.sequence[_index]
          : null;

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      eventController.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    _currentAudioSourcePlayer?.pause();
    _audioSourcePlayer = getAudioSource(request.audioSourceMessage);
    _index = request.initialIndex ?? 0;
    final duration = await _currentAudioSourcePlayer.load();
    if (request.initialPosition != null) {
      await _currentAudioSourcePlayer
          .seek(request.initialPosition.inMilliseconds);
    }
    if (_playing) {
      _currentAudioSourcePlayer.play();
    }
    return LoadResponse(duration: duration);
  }

  Future<Duration> loadUri(final Uri uri) async {
    transition(ProcessingStateMessage.loading);
    final src = uri.toString();
    if (src != _audioElement.src) {
      _durationCompleter = Completer<num>();
      _audioElement.src = src;
      _audioElement.preload = 'auto';
      _audioElement.load();
      try {
        await _durationCompleter.future;
      } on MediaError catch (e) {
        throw PlatformException(
            code: "${e.code}", message: "Failed to load URL");
      } finally {
        _durationCompleter = null;
      }
    }
    transition(ProcessingStateMessage.ready);
    final seconds = _audioElement.duration;
    return seconds.isFinite
        ? Duration(milliseconds: (seconds * 1000).toInt())
        : null;
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    await _play();
    return PlayResponse();
  }

  Future<void> _play() async {
    _playing = true;
    await _currentAudioSourcePlayer.play();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    _playing = false;
    _currentAudioSourcePlayer.pause();
    return PauseResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async {
    _audioElement.volume = request.volume;
    return SetVolumeResponse();
  }

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async {
    _audioElement.playbackRate = request.speed;
    return SetSpeedResponse();
  }

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async {
    _loopMode = request.loopMode;
    return SetLoopModeResponse();
  }

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
      SetShuffleModeRequest request) async {
    _shuffleModeEnabled = request.shuffleMode == ShuffleModeMessage.all;
    return SetShuffleModeResponse();
  }

  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(
      SetShuffleOrderRequest request) async {
    void internalSetShuffleOrder(AudioSourceMessage sourceMessage) {
      final audioSourcePlayer = _audioSourcePlayers[sourceMessage.id];
      if (audioSourcePlayer == null) return;
      if (sourceMessage is ConcatenatingAudioSourceMessage &&
          audioSourcePlayer is ConcatenatingAudioSourcePlayer) {
        audioSourcePlayer.setShuffleOrder(sourceMessage.shuffleOrder);
        for (var childMessage in sourceMessage.children) {
          internalSetShuffleOrder(childMessage);
        }
      } else if (sourceMessage is LoopingAudioSourceMessage) {
        internalSetShuffleOrder(sourceMessage.child);
      }
    }

    internalSetShuffleOrder(request.audioSourceMessage);
    return SetShuffleOrderResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    await _seek(request.position.inMilliseconds, request.index);
    return SeekResponse();
  }

  Future<void> _seek(int position, int newIndex) async {
    int index = newIndex ?? _index;
    if (index != _index) {
      _currentAudioSourcePlayer.pause();
      _index = index;
      await _currentAudioSourcePlayer.load();
      await _currentAudioSourcePlayer.seek(position);
      if (_playing) {
        _currentAudioSourcePlayer.play();
      }
    } else {
      await _currentAudioSourcePlayer.seek(position);
    }
  }

  ConcatenatingAudioSourcePlayer _concatenating(String playerId) =>
      _audioSourcePlayers[playerId] as ConcatenatingAudioSourcePlayer;

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
      ConcatenatingInsertAllRequest request) async {
    _concatenating(request.id)
        .insertAll(request.index, getAudioSources(request.children));
    _concatenating(request.id).setShuffleOrder(request.shuffleOrder);
    if (request.index <= _index) {
      _index += request.children.length;
    }
    return ConcatenatingInsertAllResponse();
  }

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
      ConcatenatingRemoveRangeRequest request) async {
    if (_index >= request.startIndex && _index < request.endIndex && _playing) {
      // Pause if removing current item
      _currentAudioSourcePlayer.pause();
    }
    _concatenating(request.id)
        .removeRange(request.startIndex, request.endIndex);
    _concatenating(request.id).setShuffleOrder(request.shuffleOrder);
    if (_index >= request.startIndex && _index < request.endIndex) {
      // Skip backward if there's nothing after this
      if (request.startIndex >= _audioSourcePlayer.sequence.length) {
        _index = request.startIndex - 1;
      } else {
        _index = request.startIndex;
      }
      // Resume playback at the new item (if it exists)
      if (_playing && _currentAudioSourcePlayer != null) {
        await _currentAudioSourcePlayer.load();
        _currentAudioSourcePlayer.play();
      }
    } else if (request.endIndex <= _index) {
      // Reflect that the current item has shifted its position
      _index -= (request.endIndex - request.startIndex);
    }
    return ConcatenatingRemoveRangeResponse();
  }

  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(
      ConcatenatingMoveRequest request) async {
    _concatenating(request.id).move(request.currentIndex, request.newIndex);
    _concatenating(request.id).setShuffleOrder(request.shuffleOrder);
    if (request.currentIndex == _index) {
      _index = request.newIndex;
    } else if (request.currentIndex < _index && request.newIndex >= _index) {
      _index--;
    } else if (request.currentIndex > _index && request.newIndex <= _index) {
      _index++;
    }
    return ConcatenatingMoveResponse();
  }

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
      SetAndroidAudioAttributesRequest request) async {
    return SetAndroidAudioAttributesResponse();
  }

  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
      setAutomaticallyWaitsToMinimizeStalling(
          SetAutomaticallyWaitsToMinimizeStallingRequest request) async {
    return SetAutomaticallyWaitsToMinimizeStallingResponse();
  }

  @override
  Duration getCurrentPosition() => _currentAudioSourcePlayer?.position;

  @override
  Duration getBufferedPosition() => _currentAudioSourcePlayer?.bufferedPosition;

  @override
  Duration getDuration() => _currentAudioSourcePlayer?.duration;

  @override
  Future<void> release() async {
    _currentAudioSourcePlayer?.pause();
    _audioElement.removeAttribute('src');
    _audioElement.load();
    transition(ProcessingStateMessage.none);
    return await super.release();
  }

  List<AudioSourcePlayer> getAudioSources(List messages) =>
      messages.map((message) => getAudioSource(message)).toList();

  AudioSourcePlayer getAudioSource(AudioSourceMessage audioSourceMessage) {
    final String id = audioSourceMessage.id;
    var audioSourcePlayer = _audioSourcePlayers[id];
    if (audioSourcePlayer == null) {
      audioSourcePlayer = decodeAudioSource(audioSourceMessage);
      _audioSourcePlayers[id] = audioSourcePlayer;
    }
    return audioSourcePlayer;
  }

  AudioSourcePlayer decodeAudioSource(AudioSourceMessage audioSourceMessage) {
    if (audioSourceMessage is ProgressiveAudioSourceMessage) {
      return ProgressiveAudioSourcePlayer(this, audioSourceMessage.id,
          Uri.parse(audioSourceMessage.uri), audioSourceMessage.headers);
    } else if (audioSourceMessage is DashAudioSourceMessage) {
      return DashAudioSourcePlayer(this, audioSourceMessage.id,
          Uri.parse(audioSourceMessage.uri), audioSourceMessage.headers);
    } else if (audioSourceMessage is HlsAudioSourceMessage) {
      return HlsAudioSourcePlayer(this, audioSourceMessage.id,
          Uri.parse(audioSourceMessage.uri), audioSourceMessage.headers);
    } else if (audioSourceMessage is ConcatenatingAudioSourceMessage) {
      return ConcatenatingAudioSourcePlayer(
          this,
          audioSourceMessage.id,
          getAudioSources(audioSourceMessage.children),
          audioSourceMessage.useLazyPreparation,
          audioSourceMessage.shuffleOrder);
    } else if (audioSourceMessage is ClippingAudioSourceMessage) {
      return ClippingAudioSourcePlayer(
          this,
          audioSourceMessage.id,
          getAudioSource(audioSourceMessage.child),
          audioSourceMessage.start,
          audioSourceMessage.end);
    } else if (audioSourceMessage is LoopingAudioSourceMessage) {
      return LoopingAudioSourcePlayer(this, audioSourceMessage.id,
          getAudioSource(audioSourceMessage.child), audioSourceMessage.count);
    } else {
      throw Exception("Unknown AudioSource type: $audioSourceMessage");
    }
  }
}

abstract class AudioSourcePlayer {
  Html5AudioPlayer html5AudioPlayer;
  final String id;

  AudioSourcePlayer(this.html5AudioPlayer, this.id);

  List<IndexedAudioSourcePlayer> get sequence;

  List<int> get shuffleIndices;
}

abstract class IndexedAudioSourcePlayer extends AudioSourcePlayer {
  IndexedAudioSourcePlayer(Html5AudioPlayer html5AudioPlayer, String id)
      : super(html5AudioPlayer, id);

  Future<Duration> load();

  Future<void> play();

  Future<void> pause();

  Future<void> seek(int position);

  Future<void> complete();

  Future<void> timeUpdated(double seconds) async {}

  Duration get duration;

  Duration get position;

  Duration get bufferedPosition;

  AudioElement get _audioElement => html5AudioPlayer._audioElement;

  @override
  String toString() => "${this.runtimeType}";
}

abstract class UriAudioSourcePlayer extends IndexedAudioSourcePlayer {
  final Uri uri;
  final Map headers;
  double _resumePos;
  Duration _duration;
  Completer _completer;

  UriAudioSourcePlayer(
      Html5AudioPlayer html5AudioPlayer, String id, this.uri, this.headers)
      : super(html5AudioPlayer, id);

  @override
  List<IndexedAudioSourcePlayer> get sequence => [this];

  @override
  List<int> get shuffleIndices => [0];

  @override
  Future<Duration> load() async {
    _resumePos = 0.0;
    return _duration = await html5AudioPlayer.loadUri(uri);
  }

  @override
  Future<void> play() async {
    _audioElement.currentTime = _resumePos;
    _audioElement.play();
    _completer = Completer();
    await _completer.future;
    _completer = null;
  }

  @override
  Future<void> pause() async {
    _resumePos = _audioElement.currentTime;
    _audioElement.pause();
    _interruptPlay();
  }

  @override
  Future<void> seek(int position) async {
    _audioElement.currentTime = _resumePos = position / 1000.0;
  }

  @override
  Future<void> complete() async {
    _interruptPlay();
    html5AudioPlayer.onEnded();
  }

  _interruptPlay() {
    if (_completer?.isCompleted == false) {
      _completer.complete();
    }
  }

  @override
  Duration get duration {
    return _duration;
    //final seconds = _audioElement.duration;
    //return seconds.isFinite
    //    ? Duration(milliseconds: (seconds * 1000).toInt())
    //    : null;
  }

  @override
  Duration get position {
    double seconds = _audioElement.currentTime;
    return Duration(milliseconds: (seconds * 1000).toInt());
  }

  @override
  Duration get bufferedPosition {
    if (_audioElement.buffered.length > 0) {
      return Duration(
          milliseconds:
              (_audioElement.buffered.end(_audioElement.buffered.length - 1) *
                      1000)
                  .toInt());
    } else {
      return Duration.zero;
    }
  }
}

class ProgressiveAudioSourcePlayer extends UriAudioSourcePlayer {
  ProgressiveAudioSourcePlayer(
      Html5AudioPlayer html5AudioPlayer, String id, Uri uri, Map headers)
      : super(html5AudioPlayer, id, uri, headers);
}

class DashAudioSourcePlayer extends UriAudioSourcePlayer {
  DashAudioSourcePlayer(
      Html5AudioPlayer html5AudioPlayer, String id, Uri uri, Map headers)
      : super(html5AudioPlayer, id, uri, headers);
}

class HlsAudioSourcePlayer extends UriAudioSourcePlayer {
  HlsAudioSourcePlayer(
      Html5AudioPlayer html5AudioPlayer, String id, Uri uri, Map headers)
      : super(html5AudioPlayer, id, uri, headers);
}

class ConcatenatingAudioSourcePlayer extends AudioSourcePlayer {
  final List<AudioSourcePlayer> audioSourcePlayers;
  final bool useLazyPreparation;
  List<int> _shuffleOrder;

  ConcatenatingAudioSourcePlayer(Html5AudioPlayer html5AudioPlayer, String id,
      this.audioSourcePlayers, this.useLazyPreparation, List<int> shuffleOrder)
      : _shuffleOrder = shuffleOrder,
        super(html5AudioPlayer, id);

  @override
  List<IndexedAudioSourcePlayer> get sequence =>
      audioSourcePlayers.expand((p) => p.sequence).toList();

  @override
  List<int> get shuffleIndices {
    final order = <int>[];
    var offset = order.length;
    final childOrders = <List<int>>[];
    for (var audioSourcePlayer in audioSourcePlayers) {
      final childShuffleIndices = audioSourcePlayer.shuffleIndices;
      childOrders.add(childShuffleIndices.map((i) => i + offset).toList());
      offset += childShuffleIndices.length;
    }
    for (var i = 0; i < childOrders.length; i++) {
      order.addAll(childOrders[_shuffleOrder[i]]);
    }
    return order;
  }

  void setShuffleOrder(List<int> shuffleOrder) {
    _shuffleOrder = shuffleOrder;
  }

  insertAll(int index, List<AudioSourcePlayer> players) {
    audioSourcePlayers.insertAll(index, players);
    for (var i = 0; i < audioSourcePlayers.length; i++) {
      if (_shuffleOrder[i] >= index) {
        _shuffleOrder[i] += players.length;
      }
    }
  }

  removeRange(int start, int end) {
    audioSourcePlayers.removeRange(start, end);
    for (var i = 0; i < audioSourcePlayers.length; i++) {
      if (_shuffleOrder[i] >= end) {
        _shuffleOrder[i] -= (end - start);
      }
    }
  }

  move(int currentIndex, int newIndex) {
    audioSourcePlayers.insert(
        newIndex, audioSourcePlayers.removeAt(currentIndex));
  }
}

class ClippingAudioSourcePlayer extends IndexedAudioSourcePlayer {
  final UriAudioSourcePlayer audioSourcePlayer;
  final Duration start;
  final Duration end;
  Completer<ClipInterruptReason> _completer;
  double _resumePos;
  Duration _duration;

  ClippingAudioSourcePlayer(Html5AudioPlayer html5AudioPlayer, String id,
      this.audioSourcePlayer, this.start, this.end)
      : super(html5AudioPlayer, id);

  @override
  List<IndexedAudioSourcePlayer> get sequence => [this];

  @override
  List<int> get shuffleIndices => [0];

  @override
  Future<Duration> load() async {
    _resumePos = (start ?? Duration.zero).inMilliseconds / 1000.0;
    Duration fullDuration =
        await html5AudioPlayer.loadUri(audioSourcePlayer.uri);
    _audioElement.currentTime = _resumePos;
    _duration = Duration(
        milliseconds: min((end ?? fullDuration).inMilliseconds,
                fullDuration.inMilliseconds) -
            (start ?? Duration.zero).inMilliseconds);
    return _duration;
  }

  double get remaining => end.inMilliseconds / 1000 - _audioElement.currentTime;

  @override
  Future<void> play() async {
    _interruptPlay(ClipInterruptReason.simultaneous);
    _audioElement.currentTime = _resumePos;
    _audioElement.play();
    _completer = Completer<ClipInterruptReason>();
    ClipInterruptReason reason;
    while ((reason = await _completer.future) == ClipInterruptReason.seek) {
      _completer = Completer<ClipInterruptReason>();
    }
    if (reason == ClipInterruptReason.end) {
      html5AudioPlayer.onEnded();
    }
    _completer = null;
  }

  @override
  Future<void> pause() async {
    _interruptPlay(ClipInterruptReason.pause);
    _resumePos = _audioElement.currentTime;
    _audioElement.pause();
  }

  @override
  Future<void> seek(int position) async {
    _interruptPlay(ClipInterruptReason.seek);
    _audioElement.currentTime =
        _resumePos = start.inMilliseconds / 1000.0 + position / 1000.0;
  }

  @override
  Future<void> complete() async {
    _interruptPlay(ClipInterruptReason.end);
  }

  @override
  Future<void> timeUpdated(double seconds) async {
    if (end != null) {
      if (seconds >= end.inMilliseconds / 1000) {
        _interruptPlay(ClipInterruptReason.end);
      }
    }
  }

  @override
  Duration get duration {
    return _duration;
  }

  @override
  Duration get position {
    double seconds = _audioElement.currentTime;
    var position = Duration(milliseconds: (seconds * 1000).toInt());
    if (start != null) {
      position -= start;
    }
    if (position < Duration.zero) {
      position = Duration.zero;
    }
    return position;
  }

  @override
  Duration get bufferedPosition {
    if (_audioElement.buffered.length > 0) {
      var seconds =
          _audioElement.buffered.end(_audioElement.buffered.length - 1);
      var position = Duration(milliseconds: (seconds * 1000).toInt());
      if (start != null) {
        position -= start;
      }
      if (position < Duration.zero) {
        position = Duration.zero;
      }
      if (duration != null && position > duration) {
        position = duration;
      }
      return position;
    } else {
      return Duration.zero;
    }
  }

  _interruptPlay(ClipInterruptReason reason) {
    if (_completer?.isCompleted == false) {
      _completer.complete(reason);
    }
  }
}

enum ClipInterruptReason { end, pause, seek, simultaneous }

class LoopingAudioSourcePlayer extends AudioSourcePlayer {
  final AudioSourcePlayer audioSourcePlayer;
  final int count;

  LoopingAudioSourcePlayer(Html5AudioPlayer html5AudioPlayer, String id,
      this.audioSourcePlayer, this.count)
      : super(html5AudioPlayer, id);

  @override
  List<IndexedAudioSourcePlayer> get sequence =>
      List.generate(count, (i) => audioSourcePlayer)
          .expand((p) => p.sequence)
          .toList();

  @override
  List<int> get shuffleIndices {
    final order = <int>[];
    var offset = order.length;
    for (var i = 0; i < count; i++) {
      final childShuffleOrder = audioSourcePlayer.shuffleIndices;
      order.addAll(childShuffleOrder.map((i) => i + offset).toList());
      offset += childShuffleOrder.length;
    }
    return order;
  }
}
