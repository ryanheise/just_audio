import 'dart:async';
import 'dart:html';
import 'dart:math';

import 'package:async/async.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:just_audio/just_audio.dart';

final Random _random = Random();

class JustAudioPlugin {
  static void registerWith(Registrar registrar) {
    final MethodChannel channel = MethodChannel(
        'com.ryanheise.just_audio.methods',
        const StandardMethodCodec(),
        registrar.messenger);
    final JustAudioPlugin instance = JustAudioPlugin(registrar);
    channel.setMethodCallHandler(instance.handleMethodCall);
  }

  final Registrar registrar;

  JustAudioPlugin(this.registrar);

  Future<dynamic> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'init':
        final String id = call.arguments[0];
        new Html5AudioPlayer(id: id, registrar: registrar);
        return null;
      case 'setIosCategory':
        return null;
      default:
        throw PlatformException(code: 'Unimplemented');
    }
  }
}

abstract class JustAudioPlayer {
  final String id;
  final Registrar registrar;
  final MethodChannel methodChannel;
  final PluginEventChannel eventChannel;
  final StreamController eventController = StreamController();
  AudioPlaybackState _state = AudioPlaybackState.none;
  bool _buffering = false;
  int _index;

  JustAudioPlayer({@required this.id, @required this.registrar})
      : methodChannel = MethodChannel('com.ryanheise.just_audio.methods.$id',
            const StandardMethodCodec(), registrar.messenger),
        eventChannel = PluginEventChannel('com.ryanheise.just_audio.events.$id',
            const StandardMethodCodec(), registrar.messenger) {
    methodChannel.setMethodCallHandler(_methodHandler);
    eventChannel.controller = eventController;
  }

  Future<dynamic> _methodHandler(MethodCall call) async {
    try {
      final args = call.arguments;
      switch (call.method) {
        case 'load':
          return await load(args[0]);
        case 'play':
          return await play();
        case 'pause':
          return await pause();
        case 'stop':
          return await stop();
        case 'setVolume':
          return await setVolume(args[0]);
        case 'setSpeed':
          return await setSpeed(args[0]);
        case 'setLoopMode':
          return await setLoopMode(args[0]);
        case 'setShuffleModeEnabled':
          return await setShuffleModeEnabled(args[0]);
        case 'seek':
          return await seek(args[0], args[1]);
        case 'dispose':
          return dispose();
        case 'concatenating.add':
          return await concatenatingAdd(args[0], args[1]);
        case "concatenating.insert":
          return await concatenatingInsert(args[0], args[1], args[2]);
        case "concatenating.addAll":
          return await concatenatingAddAll(args[0], args[1]);
        case "concatenating.insertAll":
          return await concatenatingInsertAll(args[0], args[1], args[2]);
        case "concatenating.removeAt":
          return await concatenatingRemoveAt(args[0], args[1]);
        case "concatenating.removeRange":
          return await concatenatingRemoveRange(args[0], args[1], args[2]);
        case "concatenating.move":
          return await concatenatingMove(args[0], args[1], args[2]);
        case "concatenating.clear":
          return await concatenatingClear(args[0]);
        default:
          throw PlatformException(code: 'Unimplemented');
      }
    } catch (e, stacktrace) {
      print("$stacktrace");
      rethrow;
    }
  }

  Future<int> load(Map source);

  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  Future<void> setVolume(double volume);

  Future<void> setSpeed(double speed);

  Future<void> setLoopMode(int mode);

  Future<void> setShuffleModeEnabled(bool enabled);

  Future<void> seek(int position, int index);

  @mustCallSuper
  void dispose() {
    eventController.close();
  }

  Duration getCurrentPosition();

  Duration getDuration();

  concatenatingAdd(String playerId, Map source);

  concatenatingInsert(String playerId, int index, Map source);

  concatenatingAddAll(String playerId, List sources);

  concatenatingInsertAll(String playerId, int index, List sources);

  concatenatingRemoveAt(String playerId, int index);

  concatenatingRemoveRange(String playerId, int start, int end);

  concatenatingMove(String playerId, int currentIndex, int newIndex);

  concatenatingClear(String playerId);

  broadcastPlaybackEvent() {
    var updateTime = DateTime.now().millisecondsSinceEpoch;
    eventController.add({
      'state': _state.index,
      'buffering': _buffering,
      'updatePosition': getCurrentPosition()?.inMilliseconds,
      'updateTime': updateTime,
      // TODO: buffered position
      'bufferedPosition': getCurrentPosition()?.inMilliseconds,
      // TODO: Icy Metadata
      'icyMetadata': null,
      'duration': getDuration()?.inMilliseconds,
      'currentIndex': _index,
    });
  }

  transition(AudioPlaybackState state) {
    _state = state;
    broadcastPlaybackEvent();
  }
}

class Html5AudioPlayer extends JustAudioPlayer {
  AudioElement _audioElement = AudioElement();
  Completer _durationCompleter;
  AudioSourcePlayer _audioSourcePlayer;
  LoopMode _loopMode = LoopMode.off;
  bool _shuffleModeEnabled = false;
  bool _playing = false;
  final Map<String, AudioSourcePlayer> _audioSourcePlayers = {};

  Html5AudioPlayer({@required String id, @required Registrar registrar})
      : super(id: id, registrar: registrar) {
    _audioElement.addEventListener('durationchange', (event) {
      _durationCompleter?.complete();
    });
    _audioElement.addEventListener('error', (event) {
      _durationCompleter?.completeError(_audioElement.error);
    });
    _audioElement.addEventListener('ended', (event) async {
      onEnded();
    });
    _audioElement.addEventListener('seek', (event) {
      _buffering = true;
      broadcastPlaybackEvent();
    });
    _audioElement.addEventListener('seeked', (event) {
      _buffering = false;
      broadcastPlaybackEvent();
    });
  }

  List<int> get order {
    final sequence = _audioSourcePlayer.sequence;
    List<int> order = List<int>(sequence.length);
    if (_shuffleModeEnabled) {
      order = _audioSourcePlayer.shuffleOrder;
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
    if (_loopMode == LoopMode.one) {
      await seek(0, null);
      play();
    } else {
      final order = this.order;
      final orderInv = getInv(order);
      if (orderInv[_index] + 1 < order.length) {
        // move to next item
        _index = order[orderInv[_index] + 1];
        await _currentAudioSourcePlayer.load();
        // Should always be true...
        if (_playing) {
          play();
        }
      } else {
        // reached end of playlist
        if (_loopMode == LoopMode.all) {
          // Loop back to the beginning
          if (order.length == 1) {
            await seek(0, null);
            await play();
          } else {
            _index = order[0];
            await _currentAudioSourcePlayer.load();
            // Should always be true...
            if (_playing) {
              await play();
            }
          }
        } else {
          _playing = false;
          transition(AudioPlaybackState.completed);
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
  Future<int> load(Map source) async {
    _currentAudioSourcePlayer?.pause();
    _audioSourcePlayer = getAudioSource(source);
    _index = 0;
    if (_shuffleModeEnabled) {
      _audioSourcePlayer?.shuffle(0, _index);
    }
    return (await _currentAudioSourcePlayer.load()).inMilliseconds;
  }

  Future<Duration> loadUri(final Uri uri) async {
    transition(AudioPlaybackState.connecting);
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
    transition(AudioPlaybackState.stopped);
    final seconds = _audioElement.duration;
    return seconds.isFinite
        ? Duration(milliseconds: (seconds * 1000).toInt())
        : null;
  }

  @override
  Future<void> play() async {
    _playing = true;
    _currentAudioSourcePlayer.play();
    transition(AudioPlaybackState.playing);
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _currentAudioSourcePlayer.pause();
    transition(AudioPlaybackState.paused);
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _currentAudioSourcePlayer.stop();
    transition(AudioPlaybackState.stopped);
  }

  @override
  Future<void> setVolume(double volume) async {
    _audioElement.volume = volume;
  }

  @override
  Future<void> setSpeed(double speed) async {
    _audioElement.playbackRate = speed;
  }

  @override
  Future<void> setLoopMode(int mode) async {
    _loopMode = LoopMode.values[mode];
  }

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {
    _shuffleModeEnabled = enabled;
    if (enabled) {
      _audioSourcePlayer?.shuffle(0, _index);
    }
  }

  @override
  Future<void> seek(int position, int newIndex) async {
    int index = newIndex ?? _index;
    if (index != _index) {
      _currentAudioSourcePlayer.pause();
      _index = index;
      await _currentAudioSourcePlayer.load();
      await _currentAudioSourcePlayer.seek(position);
      if (_playing) {
        await play();
      }
    } else {
      await _currentAudioSourcePlayer.seek(position);
    }
  }

  ConcatenatingAudioSourcePlayer _concatenating(String playerId) =>
      _audioSourcePlayers[playerId] as ConcatenatingAudioSourcePlayer;

  concatenatingAdd(String playerId, Map source) {
    final playlist = _concatenating(playerId);
    playlist.add(getAudioSource(source));
  }

  concatenatingInsert(String playerId, int index, Map source) {
    _concatenating(playerId).insert(index, getAudioSource(source));
    if (index <= _index) {
      _index++;
    }
  }

  concatenatingAddAll(String playerId, List sources) {
    _concatenating(playerId).addAll(getAudioSources(sources));
  }

  concatenatingInsertAll(String playerId, int index, List sources) {
    _concatenating(playerId).insertAll(index, getAudioSources(sources));
    if (index <= _index) {
      _index += sources.length;
    }
  }

  concatenatingRemoveAt(String playerId, int index) async {
    // Pause if removing current item
    if (_index == index && _playing) {
      _currentAudioSourcePlayer.pause();
    }
    _concatenating(playerId).removeAt(index);
    if (_index == index) {
      // Skip backward if there's nothing after this
      if (index == _audioSourcePlayer.sequence.length) {
        _index--;
      }
      // Resume playback at the new item (if it exists)
      if (_playing && _currentAudioSourcePlayer != null) {
        await _currentAudioSourcePlayer.load();
        _currentAudioSourcePlayer.play();
      }
    } else if (index < _index) {
      // Reflect that the current item has shifted its position
      _index--;
    }
  }

  concatenatingRemoveRange(String playerId, int start, int end) async {
    if (_index >= start && _index < end && _playing) {
      // Pause if removing current item
      _currentAudioSourcePlayer.pause();
    }
    _concatenating(playerId).removeRange(start, end);
    if (_index >= start && _index < end) {
      // Skip backward if there's nothing after this
      if (start >= _audioSourcePlayer.sequence.length) {
        _index = start - 1;
      } else {
        _index = start;
      }
      // Resume playback at the new item (if it exists)
      if (_playing && _currentAudioSourcePlayer != null) {
        await _currentAudioSourcePlayer.load();
        _currentAudioSourcePlayer.play();
      }
    } else if (end <= _index) {
      // Reflect that the current item has shifted its position
      _index -= (end - start);
    }
  }

  concatenatingMove(String playerId, int currentIndex, int newIndex) {
    _concatenating(playerId).move(currentIndex, newIndex);
    if (currentIndex == _index) {
      _index = newIndex;
    } else if (currentIndex < _index && newIndex >= _index) {
      _index--;
    } else if (currentIndex > _index && newIndex <= _index) {
      _index++;
    }
  }

  concatenatingClear(String playerId) {
    _currentAudioSourcePlayer.stop();
    _concatenating(playerId).clear();
  }

  @override
  Duration getCurrentPosition() => _currentAudioSourcePlayer?.position;

  @override
  Duration getDuration() => _currentAudioSourcePlayer?.duration;

  @override
  void dispose() {
    _currentAudioSourcePlayer?.pause();
    _audioElement.removeAttribute('src');
    _audioElement.load();
    transition(AudioPlaybackState.none);
    super.dispose();
  }

  List<AudioSourcePlayer> getAudioSources(List json) =>
      json.map((s) => getAudioSource(s)).toList();

  AudioSourcePlayer getAudioSource(Map json) {
    final String id = json['id'];
    var audioSourcePlayer = _audioSourcePlayers[id];
    if (audioSourcePlayer == null) {
      audioSourcePlayer = decodeAudioSource(json);
      _audioSourcePlayers[id] = audioSourcePlayer;
    }
    return audioSourcePlayer;
  }

  AudioSourcePlayer decodeAudioSource(Map json) {
    try {
      switch (json['type']) {
        case 'progressive':
          return ProgressiveAudioSourcePlayer(
              this, json['id'], Uri.parse(json['uri']), json['headers']);
        case "dash":
          return DashAudioSourcePlayer(
              this, json['id'], Uri.parse(json['uri']), json['headers']);
        case "hls":
          return HlsAudioSourcePlayer(
              this, json['id'], Uri.parse(json['uri']), json['headers']);
        case "concatenating":
          return ConcatenatingAudioSourcePlayer(
              this,
              json['id'],
              getAudioSources(json['audioSources']),
              json['useLazyPreparation']);
        case "clipping":
          return ClippingAudioSourcePlayer(
              this,
              json['id'],
              getAudioSource(json['audioSource']),
              Duration(milliseconds: json['start']),
              Duration(milliseconds: json['end']));
        case "looping":
          return LoopingAudioSourcePlayer(this, json['id'],
              getAudioSource(json['audioSource']), json['count']);
        default:
          throw Exception("Unknown AudioSource type: " + json['type']);
      }
    } catch (e, stacktrace) {
      print("$stacktrace");
      rethrow;
    }
  }
}

abstract class AudioSourcePlayer {
  Html5AudioPlayer html5AudioPlayer;
  final String id;

  AudioSourcePlayer(this.html5AudioPlayer, this.id);

  List<IndexedAudioSourcePlayer> get sequence;

  List<int> get shuffleOrder;

  int shuffle(int treeIndex, int currentIndex);
}

abstract class IndexedAudioSourcePlayer extends AudioSourcePlayer {
  IndexedAudioSourcePlayer(Html5AudioPlayer html5AudioPlayer, String id)
      : super(html5AudioPlayer, id);

  Future<Duration> load();

  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  Future<void> seek(int position);

  Duration get duration;

  Duration get position;

  AudioElement get _audioElement => html5AudioPlayer._audioElement;

  @override
  int shuffle(int treeIndex, int currentIndex) => treeIndex + 1;

  @override
  String toString() => "${this.runtimeType}";
}

abstract class UriAudioSourcePlayer extends IndexedAudioSourcePlayer {
  final Uri uri;
  final Map headers;
  double _resumePos;
  Duration _duration;

  UriAudioSourcePlayer(
      Html5AudioPlayer html5AudioPlayer, String id, this.uri, this.headers)
      : super(html5AudioPlayer, id);

  @override
  List<IndexedAudioSourcePlayer> get sequence => [this];

  @override
  List<int> get shuffleOrder => [0];

  @override
  Future<Duration> load() async {
    _resumePos = 0.0;
    return _duration = await html5AudioPlayer.loadUri(uri);
  }

  @override
  Future<void> play() async {
    _audioElement.currentTime = _resumePos;
    _audioElement.play();
  }

  @override
  Future<void> pause() async {
    _resumePos = _audioElement.currentTime;
    _audioElement.pause();
  }

  @override
  Future<void> seek(int position) async {
    _audioElement.currentTime = _resumePos = position / 1000.0;
  }

  @override
  Future<void> stop() async {
    _resumePos = 0.0;
    _audioElement.pause();
    _audioElement.currentTime = 0.0;
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
  static List<int> generateShuffleOrder(int length, [int firstIndex]) {
    final shuffleOrder = List<int>(length);
    for (var i = 0; i < length; i++) {
      final j = _random.nextInt(i + 1);
      shuffleOrder[i] = shuffleOrder[j];
      shuffleOrder[j] = i;
    }
    if (firstIndex != null) {
      for (var i = 1; i < length; i++) {
        if (shuffleOrder[i] == firstIndex) {
          final v = shuffleOrder[0];
          shuffleOrder[0] = shuffleOrder[i];
          shuffleOrder[i] = v;
          break;
        }
      }
    }
    return shuffleOrder;
  }

  final List<AudioSourcePlayer> audioSourcePlayers;
  final bool useLazyPreparation;
  List<int> _shuffleOrder;

  ConcatenatingAudioSourcePlayer(Html5AudioPlayer html5AudioPlayer, String id,
      this.audioSourcePlayers, this.useLazyPreparation)
      : _shuffleOrder = generateShuffleOrder(audioSourcePlayers.length),
        super(html5AudioPlayer, id);

  @override
  List<IndexedAudioSourcePlayer> get sequence =>
      audioSourcePlayers.expand((p) => p.sequence).toList();

  @override
  List<int> get shuffleOrder {
    final order = <int>[];
    var offset = order.length;
    final childOrders = <List<int>>[];
    for (var audioSourcePlayer in audioSourcePlayers) {
      final childShuffleOrder = audioSourcePlayer.shuffleOrder;
      childOrders.add(childShuffleOrder.map((i) => i + offset).toList());
      offset += childShuffleOrder.length;
    }
    for (var i = 0; i < childOrders.length; i++) {
      order.addAll(childOrders[_shuffleOrder[i]]);
    }
    return order;
  }

  @override
  int shuffle(int treeIndex, int currentIndex) {
    int currentChildIndex;
    for (var i = 0; i < audioSourcePlayers.length; i++) {
      final indexBefore = treeIndex;
      final child = audioSourcePlayers[i];
      treeIndex = child.shuffle(treeIndex, currentIndex);
      if (currentIndex >= indexBefore && currentIndex < treeIndex) {
        currentChildIndex = i;
      } else {}
    }
    // Shuffle so that the current child is first in the shuffle order
    _shuffleOrder =
        generateShuffleOrder(audioSourcePlayers.length, currentChildIndex);
    return treeIndex;
  }

  add(AudioSourcePlayer player) {
    audioSourcePlayers.add(player);
    _shuffleOrder.add(audioSourcePlayers.length - 1);
  }

  insert(int index, AudioSourcePlayer player) {
    audioSourcePlayers.insert(index, player);
    for (var i = 0; i < audioSourcePlayers.length; i++) {
      if (_shuffleOrder[i] >= index) {
        _shuffleOrder[i]++;
      }
    }
    _shuffleOrder.add(index);
  }

  addAll(List<AudioSourcePlayer> players) {
    audioSourcePlayers.addAll(players);
    _shuffleOrder.addAll(
        List.generate(players.length, (i) => audioSourcePlayers.length + i)
            .toList()
              ..shuffle());
  }

  insertAll(int index, List<AudioSourcePlayer> players) {
    audioSourcePlayers.insertAll(index, players);
    for (var i = 0; i < audioSourcePlayers.length; i++) {
      if (_shuffleOrder[i] >= index) {
        _shuffleOrder[i] += players.length;
      }
    }
    _shuffleOrder.addAll(
        List.generate(players.length, (i) => index + i).toList()..shuffle());
  }

  removeAt(int index) {
    audioSourcePlayers.removeAt(index);
    // 0 1 2 3
    // 3 2 0 1
    for (var i = 0; i < audioSourcePlayers.length; i++) {
      if (_shuffleOrder[i] > index) {
        _shuffleOrder[i]--;
      }
    }
    _shuffleOrder.removeWhere((i) => i == index);
  }

  removeRange(int start, int end) {
    audioSourcePlayers.removeRange(start, end);
    for (var i = 0; i < audioSourcePlayers.length; i++) {
      if (_shuffleOrder[i] >= end) {
        _shuffleOrder[i] -= (end - start);
      }
    }
    _shuffleOrder.removeWhere((i) => i >= start && i < end);
  }

  move(int currentIndex, int newIndex) {
    audioSourcePlayers.insert(
        newIndex, audioSourcePlayers.removeAt(currentIndex));
  }

  clear() {
    audioSourcePlayers.clear();
    _shuffleOrder.clear();
  }
}

class ClippingAudioSourcePlayer extends IndexedAudioSourcePlayer {
  final UriAudioSourcePlayer audioSourcePlayer;
  final Duration start;
  final Duration end;
  CancelableOperation _playOperation;
  double _resumePos;
  Duration _duration;

  ClippingAudioSourcePlayer(Html5AudioPlayer html5AudioPlayer, String id,
      this.audioSourcePlayer, this.start, this.end)
      : super(html5AudioPlayer, id);

  @override
  List<IndexedAudioSourcePlayer> get sequence => [this];

  @override
  List<int> get shuffleOrder => [0];

  @override
  Future<Duration> load() async {
    _resumePos = start.inMilliseconds / 1000.0;
    Duration fullDuration =
        await html5AudioPlayer.loadUri(audioSourcePlayer.uri);
    _audioElement.currentTime = _resumePos;
    _duration = Duration(
        milliseconds: min(end.inMilliseconds, fullDuration.inMilliseconds) -
            start.inMilliseconds);
    return _duration;
  }

  @override
  Future<void> play() async {
    _interruptPlay();
    //_playing = true;
    final duration =
        end == null ? null : end.inMilliseconds / 1000 - _resumePos;

    _audioElement.currentTime = _resumePos;
    _audioElement.play();
    if (duration != null) {
      _playOperation = CancelableOperation.fromFuture(Future.delayed(Duration(
              milliseconds: duration * 1000 ~/ _audioElement.playbackRate)))
          .then((_) {
        _playOperation = null;
        pause();
        html5AudioPlayer.onEnded();
      });
    }
  }

  @override
  Future<void> pause() async {
    _interruptPlay();
    _resumePos = _audioElement.currentTime;
    _audioElement.pause();
  }

  @override
  Future<void> seek(int position) async {
    _interruptPlay();
    _audioElement.currentTime =
        _resumePos = start.inMilliseconds / 1000.0 + position / 1000.0;
  }

  @override
  Future<void> stop() async {
    _resumePos = 0.0;
    _audioElement.pause();
    _audioElement.currentTime = start.inMilliseconds / 1000.0;
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

  _interruptPlay() {
    _playOperation?.cancel();
    _playOperation = null;
  }
}

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
  List<int> get shuffleOrder {
    final order = <int>[];
    var offset = order.length;
    for (var i = 0; i < count; i++) {
      final childShuffleOrder = audioSourcePlayer.shuffleOrder;
      order.addAll(childShuffleOrder.map((i) => i + offset).toList());
      offset += childShuffleOrder.length;
    }
    return order;
  }

  @override
  int shuffle(int treeIndex, int currentIndex) {
    for (var i = 0; i < count; i++) {
      treeIndex = audioSourcePlayer.shuffle(treeIndex, currentIndex);
    }
    return treeIndex;
  }
}
