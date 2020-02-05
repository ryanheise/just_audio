import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';

/// An object to manage playing audio from a URL, a locale file or an asset.
///
/// ```
/// final player = AudioPlayer();
/// await player.setUrl('https://foo.com/bar.mp3');
/// player.play();
/// player.pause();
/// player.play();
/// await player.stop();
/// await player.setClip(start: Duration(seconds: 10), end: Duration(seconds: 20));
/// await player.play();
/// await player.setUrl('https://foo.com/baz.mp3');
/// await player.seek(Duration(minutes: 5));
/// player.play();
/// await player.stop();
/// await player.dispose();
/// ```
///
/// You must call [dispose] to release the resources used by this player,
/// including any temporary files created to cache assets.
///
/// The [AudioPlayer] instance transitions through different states as follows:
///
/// * [AudioPlaybackState.none]: immediately after instantiation and [dispose].
/// * [AudioPlaybackState.stopped]: eventually after [setUrl], [setFilePath],
/// [setAsset] or [setClip] completes, and immediately after [stop].
/// * [AudioPlaybackState.paused]: after [pause].
/// * [AudioPlaybackState.playing]: after [play].
/// * [AudioPlaybackState.connecting]: immediately after [setUrl],
/// [setFilePath] and [setAsset] while waiting for the media to load.
/// * [AudioPlaybackState.completed]: immediately after playback reaches the
/// end of the media or the end of the clip.
///
/// Additionally, after a [seek] request completes, the state will return to
/// whatever state the player was in prior to the seek request.
class AudioPlayer {
  static final _mainChannel = MethodChannel('com.ryanheise.just_audio.methods');

  static Future<MethodChannel> _init(int id) async {
    await _mainChannel.invokeMethod('init', ['$id']);
    return MethodChannel('com.ryanheise.just_audio.methods.$id');
  }

  final Future<MethodChannel> _channel;

  final int _id;

  Future<Duration> _durationFuture;

  final _durationSubject = BehaviorSubject<Duration>();

  // TODO: also broadcast this event on instantiation.
  AudioPlaybackEvent _audioPlaybackEvent = AudioPlaybackEvent(
    state: AudioPlaybackState.none,
    buffering: false,
    updatePosition: Duration.zero,
    updateTime: Duration.zero,
    speed: 1.0,
  );

  Stream<AudioPlaybackEvent> _eventChannelStream;

  StreamSubscription<AudioPlaybackEvent> _eventChannelStreamSubscription;

  final _playbackEventSubject = BehaviorSubject<AudioPlaybackEvent>();

  final _playbackStateSubject = BehaviorSubject<AudioPlaybackState>();

  final _bufferingSubject = BehaviorSubject<bool>();

  final _fullPlaybackStateSubject = BehaviorSubject<FullAudioPlaybackState>();

  double _volume = 1.0;

  double _speed = 1.0;

  /// Creates an [AudioPlayer].
  factory AudioPlayer() =>
      AudioPlayer._internal(DateTime.now().microsecondsSinceEpoch);

  AudioPlayer._internal(this._id) : _channel = _init(_id) {
    _eventChannelStream = EventChannel('com.ryanheise.just_audio.events.$_id')
        .receiveBroadcastStream()
        .map((data) => _audioPlaybackEvent = AudioPlaybackEvent(
              state: AudioPlaybackState.values[data[0]],
              buffering: data[1],
              updatePosition: Duration(milliseconds: data[2]),
              updateTime: Duration(milliseconds: data[3]),
              speed: _speed,
            ));
    _eventChannelStreamSubscription =
        _eventChannelStream.listen(_playbackEventSubject.add);
    _playbackStateSubject
        .addStream(playbackEventStream.map((state) => state.state).distinct());
    _bufferingSubject.addStream(
        playbackEventStream.map((state) => state.buffering).distinct());
    _fullPlaybackStateSubject.addStream(
        Rx.combineLatest2<AudioPlaybackState, bool, FullAudioPlaybackState>(
            playbackStateStream,
            bufferingStream,
            (state, buffering) => FullAudioPlaybackState(state, buffering)));
  }

  /// The duration of any media set via [setUrl], [setFilePath] or [setAsset],
  /// or null otherwise.
  Future<Duration> get durationFuture => _durationFuture;

  /// The duration of any media set via [setUrl], [setFilePath] or [setAsset].
  Stream<Duration> get durationStream => _durationSubject.stream;

  /// The latest [AudioPlaybackEvent].
  AudioPlaybackEvent get playbackEvent => _audioPlaybackEvent;

  /// A stream of [AudioPlaybackEvent]s.
  Stream<AudioPlaybackEvent> get playbackEventStream =>
      _playbackEventSubject.stream;

  /// The current [AudioPlaybackState].
  AudioPlaybackState get playbackState => _audioPlaybackEvent.state;

  /// A stream of [AudioPlaybackState]s.
  Stream<AudioPlaybackState> get playbackStateStream =>
      _playbackStateSubject.stream;

  /// Whether the player is buffering.
  bool get buffering => _audioPlaybackEvent.buffering;

  /// A stream of buffering state changes.
  Stream<bool> get bufferingStream => _bufferingSubject.stream;

  /// A stream of [FullAudioPlaybackState]s.
  Stream<FullAudioPlaybackState> get fullPlaybackStateStream =>
      _fullPlaybackStateSubject.stream;

  /// A stream periodically tracking the current position of this player.
  Stream<Duration> getPositionStream(
          [final Duration period = const Duration(milliseconds: 200)]) =>
      Rx.combineLatest2<AudioPlaybackEvent, void, Duration>(
          playbackEventStream,
          // TODO: emit periodically only in playing state.
          Stream.periodic(period),
          (state, _) => state.position);

  /// The current volume of the player.
  double get volume => _volume;

  /// The current speed of the player.
  double get speed => _speed;

  /// Loads audio media from a URL and completes with the duration of that
  /// audio, or null if this call was interrupted by another call so [setUrl],
  /// [setFilePath] or [setAsset].
  Future<Duration> setUrl(final String url) async {
    _durationFuture = _invokeMethod('setUrl', [url])
        .then((ms) => ms == null ? null : Duration(milliseconds: ms));
    final duration = await _durationFuture;
    _durationSubject.add(duration);
    return duration;
  }

  /// Loads audio media from a file and completes with the duration of that
  /// audio, or null if this call was interrupted by another call so [setUrl],
  /// [setFilePath] or [setAsset].
  Future<Duration> setFilePath(final String filePath) =>
      setUrl('file://$filePath');

  /// Loads audio media from an asset and completes with the duration of that
  /// audio, or null if this call was interrupted by another call so [setUrl],
  /// [setFilePath] or [setAsset].
  Future<Duration> setAsset(final String assetPath) async {
    final file = await _cacheFile;
    if (!file.existsSync()) {
      await file.create(recursive: true);
    }
    await file
        .writeAsBytes((await rootBundle.load(assetPath)).buffer.asUint8List());
    return await setFilePath(file.path);
  }

  Future<File> get _cacheFile async => File(p.join(
      (await getTemporaryDirectory()).path, 'just_audio_asset_cache', '$_id'));

  /// Clip the audio to the given [start] and [end] timestamps. This method
  /// cannot be called from the [AudioPlaybackState.none] state.
  Future<Duration> setClip({Duration start, Duration end}) async {
    _durationFuture =
        _invokeMethod('setClip', [start?.inMilliseconds, end?.inMilliseconds])
            .then((ms) => ms == null ? null : Duration(milliseconds: ms));
    final duration = await _durationFuture;
    _durationSubject.add(duration);
    return duration;
  }

  /// Plays the currently loaded media from the current position. The [Future]
  /// returned by this method completes when playback completes or is paused or
  /// stopped. This method can be called from any state except for:
  ///
  /// * [AudioPlaybackState.connecting]
  /// * [AudioPlaybackState.none]
  Future<void> play() async {
    StreamSubscription subscription;
    Completer completer = Completer();
    bool startedPlaying = false;
    subscription = playbackStateStream.listen((state) {
      // TODO: It will be more reliable to let the platform
      // side wait for completion since events on the flutter
      // side can lag behind the platform side.
      if (startedPlaying &&
          (state == AudioPlaybackState.paused ||
              state == AudioPlaybackState.stopped ||
              state == AudioPlaybackState.completed)) {
        subscription.cancel();
        completer.complete();
      } else if (state == AudioPlaybackState.playing) {
        startedPlaying = true;
      }
    });
    await _invokeMethod('play');
    await completer.future;
  }

  /// Pauses the currently playing media. It is legal to invoke this method
  /// only from the [AudioPlaybackState.playing] state.
  Future<void> pause() async {
    await _invokeMethod('pause');
  }

  /// Stops the currently playing media such that the next [play] invocation
  /// will start from position 0. It is legal to invoke this method only from
  /// the following states:
  ///
  /// * [AudioPlaybackState.playing]
  /// * [AudioPlaybackState.paused]
  /// * [AudioPlaybackState.completed]
  Future<void> stop() async {
    await _invokeMethod('stop');
  }

  /// Sets the volume of this player, where 1.0 is normal volume.
  Future<void> setVolume(final double volume) async {
    _volume = volume;
    await _invokeMethod('setVolume', [volume]);
  }

  /// Sets the playback speed of this player, where 1.0 is normal speed.
  Future<void> setSpeed(final double speed) async {
    _speed = speed;
    await _invokeMethod('setSpeed', [speed]);
  }

  /// Seeks to a particular position. It is legal to invoke this method from
  /// any state except for [AudioPlaybackState.none] and
  /// [AudioPlaybackState.connecting].
  Future<void> seek(final Duration position) async {
    await _invokeMethod('seek', [position.inMilliseconds]);
  }

  /// Release all resources associated with this player. You must invoke this
  /// after you are done with the player. This method can be invoked from any
  /// state except for:
  ///
  /// * [AudioPlaybackState.none]
  /// * [AudioPlaybackState.connecting]
  Future<void> dispose() async {
    if ((await _cacheFile).existsSync()) {
      (await _cacheFile).deleteSync();
    }
    await _invokeMethod('dispose');
    await _durationSubject.close();
    await _eventChannelStreamSubscription.cancel();
    await _playbackEventSubject.close();
  }

  Future<dynamic> _invokeMethod(String method, [dynamic args]) async =>
      (await _channel).invokeMethod(method, args);
}

/// Encapsulates the playback state and current position of the player.
class AudioPlaybackEvent {
  /// The current playback state.
  final AudioPlaybackState state;

  /// Whether the player is buffering.
  final bool buffering;

  /// When the last time a position discontinuity happened, as measured in time
  /// since the epoch.
  final Duration updateTime;

  /// The position at [updateTime].
  final Duration updatePosition;

  /// The playback speed.
  final double speed;

  AudioPlaybackEvent({
    @required this.state,
    @required this.buffering,
    @required this.updateTime,
    @required this.updatePosition,
    @required this.speed,
  });

  /// The current position of the player.
  Duration get position => state == AudioPlaybackState.playing && !buffering
      ? updatePosition +
          (Duration(milliseconds: DateTime.now().millisecondsSinceEpoch) -
                  updateTime) *
              speed
      : updatePosition;

  @override
  String toString() =>
      "{state=$state, updateTime=$updateTime, updatePosition=$updatePosition, speed=$speed}";
}

/// Enumerates the different playback states of a player.
enum AudioPlaybackState {
  none,
  stopped,
  paused,
  playing,
  connecting,
  completed,
}

class FullAudioPlaybackState {
  final AudioPlaybackState state;
  final bool buffering;

  FullAudioPlaybackState(this.state, this.buffering);
}
