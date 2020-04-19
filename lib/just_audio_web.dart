import 'dart:async';
import 'dart:html';

import 'package:async/async.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:just_audio/just_audio.dart';

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

  JustAudioPlayer({@required this.id, @required this.registrar})
      : methodChannel = MethodChannel('com.ryanheise.just_audio.methods.$id',
            const StandardMethodCodec(), registrar.messenger),
        eventChannel = PluginEventChannel('com.ryanheise.just_audio.events.$id',
            const StandardMethodCodec(), registrar.messenger) {
    methodChannel.setMethodCallHandler(_methodHandler);
    eventChannel.controller = eventController;
  }

  Future<dynamic> _methodHandler(MethodCall call) async {
    final args = call.arguments;
    switch (call.method) {
      case 'setUrl':
        return await setUrl(args[0]);
      case 'setClip':
        return await setClip(args[0], args[1]);
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
      case 'seek':
        return await seek(args[0]);
      case 'dispose':
        return dispose();
      default:
        throw PlatformException(code: 'Unimplemented');
    }
  }

  Future<int> setUrl(final String url);

  Future<void> setClip(int start, int end);

  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  Future<void> setVolume(double volume);

  Future<void> setSpeed(double speed);

  Future<void> seek(int position);

  @mustCallSuper
  void dispose() {
    eventController.close();
  }

  double getCurrentPosition();

  broadcastPlaybackEvent() {
    var updateTime = DateTime.now().millisecondsSinceEpoch;
    eventController.add([
      _state.index,
      _buffering,
      (getCurrentPosition() * 1000).toInt(),
      updateTime,
      // TODO: buffered position
      (getCurrentPosition() * 1000).toInt(),
    ]);
  }

  transition(AudioPlaybackState state) {
    _state = state;
    broadcastPlaybackEvent();
  }
}

class Html5AudioPlayer extends JustAudioPlayer {
  AudioElement _audioElement = AudioElement();
  Completer<num> _durationCompleter;
  double _startPos = 0.0;
  double _start = 0.0;
  double _end;
  CancelableOperation _playOperation;

  Html5AudioPlayer({@required String id, @required Registrar registrar})
      : super(id: id, registrar: registrar) {
    _audioElement.addEventListener('durationchange', (event) {
      _durationCompleter?.complete(_audioElement.duration);
    });
    _audioElement.addEventListener('ended', (event) {
      transition(AudioPlaybackState.completed);
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

  @override
  Future<int> setUrl(final String url) async {
    _interruptPlay();
    transition(AudioPlaybackState.connecting);
    _durationCompleter = Completer<num>();
    _audioElement.src = url;
    _audioElement.preload = 'auto';
    _audioElement.load();
    final duration = await _durationCompleter.future;
    transition(AudioPlaybackState.stopped);
    return (duration * 1000).toInt();
  }

  @override
  Future<void> setClip(int start, int end) async {
    _interruptPlay();
    _start = start / 1000.0;
    _end = end / 1000.0;
    _startPos = _start;
  }

  @override
  Future<void> play() async {
    _interruptPlay();
    final duration = _end == null ? null : _end - _startPos;

    _audioElement.currentTime = _startPos;
    _audioElement.play();
    if (duration != null) {
      _playOperation = CancelableOperation.fromFuture(Future.delayed(Duration(
              milliseconds: duration * 1000 ~/ _audioElement.playbackRate)))
          .then((_) {
        pause();
        _playOperation = null;
      });
    }
    transition(AudioPlaybackState.playing);
  }

  _interruptPlay() {
    if (_playOperation != null) {
      _playOperation.cancel();
      _playOperation = null;
    }
  }

  @override
  Future<void> pause() async {
    _interruptPlay();
    _startPos = _audioElement.currentTime;
    _audioElement.pause();
    transition(AudioPlaybackState.paused);
  }

  @override
  Future<void> stop() async {
    _interruptPlay();
    _startPos = _start;
    _audioElement.pause();
    _audioElement.currentTime = _start;
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
  Future<void> seek(int position) async {
    _interruptPlay();
    _startPos = _start + position / 1000.0;
    _audioElement.currentTime = _startPos;
  }

  @override
  double getCurrentPosition() => _audioElement.currentTime;

  @override
  void dispose() {
    _interruptPlay();
    _audioElement.pause();
    _audioElement.removeAttribute('src');
    _audioElement.load();
    transition(AudioPlaybackState.none);
    super.dispose();
  }
}
