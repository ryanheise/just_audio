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

  Duration _duration;

  Future<Duration> _durationFuture;

  final _durationSubject = BehaviorSubject<Duration>();

  // TODO: also broadcast this event on instantiation.
  AudioPlaybackEvent _audioPlaybackEvent = AudioPlaybackEvent(
    state: AudioPlaybackState.none,
    buffering: false,
    updatePosition: Duration.zero,
    updateTime: Duration.zero,
    bufferedPosition: Duration.zero,
    speed: 1.0,
    duration: Duration.zero,
    icyMetadata: IcyMetadata(
        info: IcyInfo(title: null, url: null),
        headers: IcyHeaders(
            bitrate: null,
            genre: null,
            name: null,
            metadataInterval: null,
            url: null,
            isPublic: null)),
  );

  Stream<AudioPlaybackEvent> _eventChannelStream;

  StreamSubscription<AudioPlaybackEvent> _eventChannelStreamSubscription;

  final _playbackEventSubject = BehaviorSubject<AudioPlaybackEvent>();

  final _playbackStateSubject = BehaviorSubject<AudioPlaybackState>();

  final _bufferingSubject = BehaviorSubject<bool>();

  final _bufferedPositionSubject = BehaviorSubject<Duration>();

  final _icyMetadataSubject = BehaviorSubject<IcyMetadata>();

  final _fullPlaybackStateSubject = BehaviorSubject<FullAudioPlaybackState>();

  double _volume = 1.0;

  double _speed = 1.0;

  bool _automaticallyWaitsToMinimizeStalling = true;

  File _cacheFile;

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
              bufferedPosition: Duration(milliseconds: data[4]),
              speed: _speed,
              duration: _duration,
              icyMetadata: data.length < 6 || data[5] == null
                  ? null
                  : IcyMetadata(
                      info: IcyInfo(title: data[5][0][0], url: data[5][0][1]),
                      headers: IcyHeaders(
                          bitrate: data[5][1][0],
                          genre: data[5][1][1],
                          name: data[5][1][2],
                          metadataInterval: data[5][1][3],
                          url: data[5][1][4],
                          isPublic: data[5][1][5])),
            ));
    _eventChannelStreamSubscription =
        _eventChannelStream.listen(_playbackEventSubject.add, onError: _playbackEventSubject.addError);
    _playbackStateSubject
        .addStream(playbackEventStream.map((state) => state.state).distinct().handleError((err,stack){ /* noop */ }));
    _bufferingSubject.addStream(
        playbackEventStream.map((state) => state.buffering).distinct().handleError((err,stack){ /* noop */ }));
    _bufferedPositionSubject.addStream(
        playbackEventStream.map((state) => state.bufferedPosition).distinct().handleError((err,stack){ /* noop */ }));
    _icyMetadataSubject.addStream(
        playbackEventStream.map((state) => state.icyMetadata).distinct().handleError((err,stack){ /* noop */ }));
    _fullPlaybackStateSubject.addStream(Rx.combineLatest3<AudioPlaybackState,
            bool, IcyMetadata, FullAudioPlaybackState>(
        playbackStateStream,
        bufferingStream,
        icyMetadataStream,
        (state, buffering, icyMetadata) =>
            FullAudioPlaybackState(state, buffering, icyMetadata)));
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

  IcyMetadata get icyMetadata => _audioPlaybackEvent.icyMetadata;

  /// A stream of buffering state changes.
  Stream<bool> get bufferingStream => _bufferingSubject.stream;

  Stream<IcyMetadata> get icyMetadataStream => _icyMetadataSubject.stream;

  /// A stream of buffered positions.
  Stream<Duration> get bufferedPositionStream =>
      _bufferedPositionSubject.stream;

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
          (state, _) => state.position).distinct();

  /// The current volume of the player.
  double get volume => _volume;

  /// The current speed of the player.
  double get speed => _speed;

  /// Whether the player should automatically delay playback in order to
  /// minimize stalling. (iOS 10.0 or later only)
  bool get automaticallyWaitsToMinimizeStalling =>
      _automaticallyWaitsToMinimizeStalling;

  /// Loads audio media from a URL and completes with the duration of that
  /// audio, or null if this call was interrupted by another call so [setUrl],
  /// [setFilePath] or [setAsset].
  ///
  /// On Android, DASH and HLS streams are detected only when the URL's path
  /// has an "mpd" or "m3u8" extension. If the URL does not have such an
  /// extension and you have no control over the server, and you also know the
  /// type of the stream in advance, you may as a workaround supply the
  /// extension as a URL fragment. e.g.
  /// https://somewhere.com/somestream?x=etc#.m3u8
  Future<Duration> setUrl(final String url) async {
    try {
      _durationFuture = _invokeMethod('setUrl', [url])
          .then((ms) => ms == null ? null : Duration(milliseconds: ms));
      _duration = await _durationFuture;
      _durationSubject.add(_duration);
      return _duration;
    } on PlatformException catch (e) {
      return Future.error(e.message);
    }
  }

  /// Loads audio media from a file and completes with the duration of that
  /// audio, or null if this call was interrupted by another call so [setUrl],
  /// [setFilePath] or [setAsset].
  Future<Duration> setFilePath(final String filePath) => setUrl(
      Platform.isAndroid ? File(filePath).uri.toString() : 'file://$filePath');

  /// Loads audio media from an asset and completes with the duration of that
  /// audio, or null if this call was interrupted by another call so [setUrl],
  /// [setFilePath] or [setAsset].
  Future<Duration> setAsset(final String assetPath) async {
    final file = await _getCacheFile(assetPath);
    this._cacheFile = file;
    if (!file.existsSync()) {
      await file.create(recursive: true);
    }
    await file
        .writeAsBytes((await rootBundle.load(assetPath)).buffer.asUint8List());
    return await setFilePath(file.path);
  }

  /// Get file for caching asset media with proper extension
  Future<File> _getCacheFile(final String assetPath) async => File(p.join(
      (await getTemporaryDirectory()).path,
      'just_audio_asset_cache',
      '$_id${p.extension(assetPath)}'));

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
    switch (playbackState) {
      case AudioPlaybackState.playing:
      case AudioPlaybackState.stopped:
      case AudioPlaybackState.completed:
      case AudioPlaybackState.paused:
        // Update local state immediately so that queries aren't surprised.
        _audioPlaybackEvent = _audioPlaybackEvent.copyWith(
          state: AudioPlaybackState.playing,
        );
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
        break;
      default:
        throw Exception(
            "Cannot call play from connecting/none states ($playbackState)");
    }
  }

  /// Pauses the currently playing media. It is legal to invoke this method
  /// only from the [AudioPlaybackState.playing] state.
  Future<void> pause() async {
    switch (playbackState) {
      case AudioPlaybackState.paused:
        break;
      case AudioPlaybackState.playing:
        // Update local state immediately so that queries aren't surprised.
        _audioPlaybackEvent = _audioPlaybackEvent.copyWith(
          state: AudioPlaybackState.paused,
        );
        // TODO: For pause, perhaps modify platform side to ensure new state
        // is broadcast before this method returns.
        await _invokeMethod('pause');
        break;
      default:
        throw Exception(
            "Can call pause only from playing and buffering states ($playbackState)");
    }
  }

  /// Stops the currently playing media such that the next [play] invocation
  /// will start from position 0. It is legal to invoke this method only from
  /// the following states:
  ///
  /// * [AudioPlaybackState.playing]
  /// * [AudioPlaybackState.paused]
  /// * [AudioPlaybackState.completed]
  Future<void> stop() async {
    switch (playbackState) {
      case AudioPlaybackState.stopped:
        break;
      case AudioPlaybackState.connecting:
      case AudioPlaybackState.completed:
      case AudioPlaybackState.playing:
      case AudioPlaybackState.paused:
        // Update local state immediately so that queries aren't surprised.
        // NOTE: Android implementation already handles this.
        // TODO: Do the same for iOS so the line below becomes unnecessary.
        _audioPlaybackEvent = _audioPlaybackEvent.copyWith(
          state: AudioPlaybackState.paused,
        );
        await _invokeMethod('stop');
        break;
      default:
        throw Exception("Cannot call stop from none state");
    }
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

  /// Sets automaticallyWaitsToMinimizeStalling for AVPlayer in iOS 10.0 or later, defaults to true.
  /// Has no effect on Android clients
  Future<void> setAutomaticallyWaitsToMinimizeStalling(
      final bool automaticallyWaitsToMinimizeStalling) async {
    _automaticallyWaitsToMinimizeStalling =
        automaticallyWaitsToMinimizeStalling;
    await _invokeMethod('setAutomaticallyWaitsToMinimizeStalling',
        [automaticallyWaitsToMinimizeStalling]);
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
    if (this._cacheFile?.existsSync() ?? false) {
      this._cacheFile?.deleteSync();
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

  /// The buffer position.
  final Duration bufferedPosition;

  /// The playback speed.
  final double speed;

  /// The media duration.
  final Duration duration;

  final IcyMetadata icyMetadata;

  AudioPlaybackEvent({
    @required this.state,
    @required this.buffering,
    @required this.updateTime,
    @required this.updatePosition,
    @required this.bufferedPosition,
    @required this.speed,
    @required this.duration,
    @required this.icyMetadata,
  });

  AudioPlaybackEvent copyWith({
    AudioPlaybackState state,
    bool buffering,
    Duration updateTime,
    Duration updatePosition,
    Duration bufferedPosition,
    double speed,
    Duration duration,
    IcyMetadata icyMetadata,
  }) =>
      AudioPlaybackEvent(
        state: state ?? this.state,
        buffering: buffering ?? this.buffering,
        updateTime: updateTime ?? this.updateTime,
        updatePosition: updatePosition ?? this.updatePosition,
        bufferedPosition: bufferedPosition ?? this.bufferedPosition,
        speed: speed ?? this.speed,
        duration: duration ?? this.duration,
        icyMetadata: icyMetadata ?? this.icyMetadata,
      );

  /// The current position of the player.
  Duration get position {
    if (state == AudioPlaybackState.playing && !buffering) {
      final result = updatePosition +
          (Duration(milliseconds: DateTime.now().millisecondsSinceEpoch) -
                  updateTime) *
              speed;
      return result <= duration ? result : duration;
    } else {
      return updatePosition;
    }
  }

  @override
  String toString() =>
      "{state=$state, updateTime=$updateTime, updatePosition=$updatePosition, speed=$speed}";
}

/// Enumerates the different playback states of a player.
///
/// If you also need access to the buffering state, use
/// [FullAudioPlaybackState].
enum AudioPlaybackState {
  none,
  stopped,
  paused,
  playing,
  connecting,
  completed,
}

/// Encapsulates the playback state and the buffering state.
///
/// These two states vary orthogonally, and so if [buffering] is true, you can
/// check [state] to determine whether this buffering is occurring during the
/// playing state or the paused state.
class FullAudioPlaybackState {
  final AudioPlaybackState state;
  final bool buffering;
  final IcyMetadata icyMetadata;

  FullAudioPlaybackState(this.state, this.buffering, this.icyMetadata);
}

class IcyInfo {
  final String title;
  final String url;

  IcyInfo({@required this.title, @required this.url});
}

class IcyHeaders {
  final int bitrate;
  final String genre;
  final String name;
  final int metadataInterval;
  final String url;
  final bool isPublic;

  IcyHeaders(
      {@required this.bitrate,
      @required this.genre,
      @required this.name,
      @required this.metadataInterval,
      @required this.url,
      @required this.isPublic});
}

class IcyMetadata {
  final IcyInfo info;
  final IcyHeaders headers;

  IcyMetadata({@required this.info, @required this.headers});
}
