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
/// await player.play();
/// await player.pause();
/// await player.play(untilPosition: Duration(minutes: 1));
/// await player.stop()
/// await player.setUrl('https://foo.com/baz.mp3');
/// await player.seek(Duration(minutes: 5));
/// await player.play();
/// await player.stop();
/// await player.dispose();
/// ```
///
/// You must call [dispose] to release the resources used by this player,
/// including any temporary files created to cache assets.
///
/// The [AudioPlayer] instance transitions through different states as follows:
///
/// * [AudioPlaybackState.none]: immediately after instantiation.
/// * [AudioPlaybackState.stopped]: eventually after [setUrl], [setFilePath] or
/// [setAsset] completes, immediately after [stop], and immediately after
/// playback naturally reaches the end of the media.
/// * [AudioPlaybackState.paused]: after [pause] and after reaching the end of
/// the requested [play] segment.
/// * [AudioPlaybackState.playing]: after [play] and after sufficiently
/// buffering during normal playback.
/// * [AudioPlaybackState.buffering]: immediately after a seek request and
/// during normal playback when the next buffer is not ready to be played.
/// * [AudioPlaybackState.connecting]: immediately after [setUrl],
/// [setFilePath] and [setAsset] while waiting for the media to load.
/// 
/// Additionally, after a [seek] request completes, the state will return to
/// whatever state the player was in prior to the seek request.
class AudioPlayer {
  static final _mainChannel =
      MethodChannel('com.ryanheise.just_audio.methods');

  static Future<MethodChannel> _createChannel(int id) async {
    await _mainChannel.invokeMethod('init', '$id');
    return MethodChannel('com.ryanheise.just_audio.methods.$id');
  }

  final Future<MethodChannel> _channel;

  final int _id;

  Future<Duration> _durationFuture;

  final _durationSubject = BehaviorSubject<Duration>();

  AudioPlayerState _audioPlayerState;

  Stream<AudioPlayerState> _eventChannelStream;

  StreamSubscription<AudioPlayerState> _eventChannelStreamSubscription;

  final _playerStateSubject = BehaviorSubject<AudioPlayerState>();

  final _playbackStateSubject = BehaviorSubject<AudioPlaybackState>();

  /// Creates an [AudioPlayer].
  factory AudioPlayer() =>
      AudioPlayer._internal(DateTime.now().microsecondsSinceEpoch);

  AudioPlayer._internal(this._id) : _channel = _createChannel(_id) {
    _eventChannelStream = EventChannel('com.ryanheise.just_audio.events.$_id')
        .receiveBroadcastStream()
        .map((data) => _audioPlayerState = AudioPlayerState(
              state: AudioPlaybackState.values[data[0]],
              updatePosition: Duration(milliseconds: data[1]),
              updateTime: Duration(milliseconds: data[2]),
            ));
    _eventChannelStreamSubscription =
        _eventChannelStream.listen(_playerStateSubject.add);
    _playbackStateSubject
        .addStream(playerStateStream.map((state) => state.state).distinct());
  }

  /// The duration of any media set via [setUrl], [setFilePath] or [setAsset],
  /// or null otherwise.
  Future<Duration> get durationFuture => _durationFuture;

  /// The duration of any media set via [setUrl], [setFilePath] or [setAsset].
  Stream<Duration> get durationStream => _durationSubject.stream;

  /// The current [AudioPlayerState].
  AudioPlayerState get playerState => _audioPlayerState;

  /// The current [AudioPlayerState].
  Stream<AudioPlayerState> get playerStateStream => _playerStateSubject.stream;

  /// The current [AudioPlaybackState].
  Stream<AudioPlaybackState> get playbackStateStream =>
      _playbackStateSubject.stream;

  /// A stream periodically tracking the current position of this player.
  Stream<Duration> getPositionStream(
          [final Duration period = const Duration(milliseconds: 200)]) =>
      Observable.combineLatest2<AudioPlayerState, void, Duration>(
          playerStateStream,
          Observable.periodic(period),
          (state, _) => state.position);

  /// Loads audio media from a URL and returns the duration of that audio.
  Future<Duration> setUrl(final String url) async {
    _durationFuture =
        _invokeMethod('setUrl', [url]).then((ms) => Duration(milliseconds: ms));
    final duration = await _durationFuture;
    _durationSubject.add(duration);
    return duration;
  }

  /// Loads audio media from a file and returns the duration of that audio.
  Future<Duration> setFilePath(final String filePath) => setUrl('file://$filePath');

  /// Loads audio media from an asset and returns the duration of that audio.
  Future<Duration> setAsset(final String assetPath) async {
    final file = await _cacheFile;
    if (!file.existsSync()) {
      await file.create(recursive: true);
    }
    await file.writeAsBytes(
        (await rootBundle.load(assetPath)).buffer.asUint8List());
    return await setFilePath(file.path);
  }

  Future<File> get _cacheFile async => File(p.join((await getTemporaryDirectory()).path, 'just_audio_asset_cache', '$_id'));

  /// Plays the currently loaded media from the current position. It is legal
  /// to invoke this method only from one of the following states:
  ///
  /// * [AudioPlaybackState.stopped]
  /// * [AudioPlaybackState.paused]
  Future<void> play({final Duration untilPosition}) async {
    StreamSubscription subscription;
    Completer completer = Completer();
    subscription = playbackStateStream
        .skip(1)
        .where((state) =>
            state == AudioPlaybackState.paused ||
            state == AudioPlaybackState.stopped)
        .listen((state) {
      subscription.cancel();
      completer.complete();
    });
    await _invokeMethod('play', [untilPosition?.inMilliseconds]);
    await completer.future;
  }

  /// Pauses the currently playing media. It is legal to invoke this method
  /// only from the following states:
  ///
  /// * [AudioPlaybackState.playing]
  /// * [AudioPlaybackState.buffering]
  Future<void> pause() async {
    await _invokeMethod('pause');
  }

  /// Stops the currently playing media such that the next [play] invocation
  /// will start from position 0. It is legal to invoke this method from any
  /// state except for:
  ///
  /// * [AudioPlaybackState.none]
  /// * [AudioPlaybackState.stopped]
  Future<void> stop() async {
    await _invokeMethod('stop');
  }

  /// Sets the volume of this player, where 1.0 is normal volume.
  Future<void> setVolume(final double volume) async {
    await _invokeMethod('setVolume', [volume]);
  }

  /// Seeks to a particular position. It is legal to invoke this method
  /// from any state except for [AudioPlaybackState.none].
  Future<void> seek(final Duration position) async {
    await _invokeMethod('seek', [position.inMilliseconds]);
  }

  /// Release all resources associated with this player. You must invoke
  /// this after you are done with the player.
  Future<void> dispose() async {
    if ((await _cacheFile).existsSync()) {
      (await _cacheFile).deleteSync();
    }
    await _invokeMethod('dispose');
    await _durationSubject.close();
    await _eventChannelStreamSubscription.cancel();
    await _playerStateSubject.close();
  }

  Future<dynamic> _invokeMethod(String method, [dynamic args]) async =>
      (await _channel).invokeMethod(method, args);
}

/// Encapsulates the playback state and current position of the player.
class AudioPlayerState {
  /// The current playback state.
  final AudioPlaybackState state;
  /// When the last time a position discontinuity happened, as measured in time
  /// since the epoch.
  final Duration updateTime;
  /// The position at [updateTime].
  final Duration updatePosition;

  AudioPlayerState({
    @required this.state,
    @required this.updateTime,
    @required this.updatePosition,
  });

  /// The current position of the player.
  Duration get position => state == AudioPlaybackState.playing
      ? updatePosition +
          (Duration(milliseconds: DateTime.now().millisecondsSinceEpoch) -
              updateTime)
      : updatePosition;
}

/// Enumerates the different playback states of a player.
enum AudioPlaybackState {
  none,
  stopped,
  paused,
  playing,
  buffering,
  connecting,
}
