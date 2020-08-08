import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

final _uuid = Uuid();

/// An object to manage playing audio from a URL, a locale file or an asset.
///
/// ```
/// final player = AudioPlayer();
/// await player.setUrl('https://foo.com/bar.mp3');
/// player.play();
/// await player.pause();
/// await player.setClip(start: Duration(seconds: 10), end: Duration(seconds: 20));
/// await player.play();
/// await player.setUrl('https://foo.com/baz.mp3');
/// await player.seek(Duration(minutes: 5));
/// player.play();
/// await player.pause();
/// await player.dispose();
/// ```
///
/// You must call [dispose] to release the resources used by this player,
/// including any temporary files created to cache assets.
class AudioPlayer {
  static final _mainChannel = MethodChannel('com.ryanheise.just_audio.methods');

  static Future<MethodChannel> _init(String id) async {
    await _mainChannel.invokeMethod('init', [id]);
    return MethodChannel('com.ryanheise.just_audio.methods.$id');
  }

  /// Configure the audio session category on iOS. This method should be called
  /// before playing any audio. It has no effect on Android or Flutter for Web.
  ///
  /// Note that the default category on iOS is [IosCategory.soloAmbient], but
  /// for a typical media app, Apple recommends setting this to
  /// [IosCategory.playback]. If you don't call this method, `just_audio` will
  /// respect any prior category that was already set on your app's audio
  /// session and will leave it alone. If it hasn't been previously set, this
  /// will be [IosCategory.soloAmbient]. But if another audio plugin in your
  /// app has configured a particular category, that will also be left alone.
  ///
  /// Note: If you use other audio plugins in conjunction with this one, it is
  /// possible that each of those audio plugins may override the setting you
  /// choose here. (You may consider asking the developers of the other plugins
  /// to provide similar configurability so that you have complete control over
  /// setting the overall category that you want for your app.)
  static Future<void> setIosCategory(IosCategory category) async {
    await _mainChannel.invokeMethod('setIosCategory', category.index);
  }

  final Future<MethodChannel> _channel;
  final String _id;
  _ProxyHttpServer _proxy;
  Stream<PlaybackEvent> _eventChannelStream;
  AudioSource _audioSource;
  Map<String, AudioSource> _audioSources = {};

  PlaybackEvent _playbackEvent;
  StreamSubscription<PlaybackEvent> _eventChannelStreamSubscription;
  final _playbackEventSubject = BehaviorSubject<PlaybackEvent>();
  Future<Duration> _durationFuture;
  final _durationSubject = BehaviorSubject<Duration>();
  final _processingStateSubject = BehaviorSubject<ProcessingState>();
  final _playingSubject = BehaviorSubject.seeded(false);
  final _volumeSubject = BehaviorSubject.seeded(1.0);
  final _speedSubject = BehaviorSubject.seeded(1.0);
  final _bufferedPositionSubject = BehaviorSubject<Duration>();
  final _icyMetadataSubject = BehaviorSubject<IcyMetadata>();
  final _playerStateSubject = BehaviorSubject<PlayerState>();
  final _currentIndexSubject = BehaviorSubject<int>();
  final _loopModeSubject = BehaviorSubject<LoopMode>();
  final _shuffleModeEnabledSubject = BehaviorSubject<bool>();
  BehaviorSubject<Duration> _positionSubject;
  bool _automaticallyWaitsToMinimizeStalling = true;

  /// Creates an [AudioPlayer].
  factory AudioPlayer() => AudioPlayer._internal(_uuid.v4());

  AudioPlayer._internal(this._id) : _channel = _init(_id) {
    _playbackEvent = PlaybackEvent(
      processingState: ProcessingState.none,
      updatePosition: Duration.zero,
      updateTime: DateTime.now(),
      bufferedPosition: Duration.zero,
      duration: null,
      icyMetadata: null,
      currentIndex: null,
    );
    _playbackEventSubject.add(_playbackEvent);
    _eventChannelStream = EventChannel('com.ryanheise.just_audio.events.$_id')
        .receiveBroadcastStream()
        .map((data) {
      try {
        //print("received raw event: $data");
        final duration = (data['duration'] ?? -1) < 0
            ? null
            : Duration(milliseconds: data['duration']);
        _durationFuture = Future.value(duration);
        if (duration != _playbackEvent.duration) {
          _durationSubject.add(duration);
        }
        _playbackEvent = PlaybackEvent(
          processingState: ProcessingState.values[data['processingState']],
          updatePosition: Duration(milliseconds: data['updatePosition']),
          updateTime: DateTime.fromMillisecondsSinceEpoch(data['updateTime']),
          bufferedPosition: Duration(milliseconds: data['bufferedPosition']),
          duration: duration,
          icyMetadata: data['icyMetadata'] == null
              ? null
              : IcyMetadata.fromJson(data['icyMetadata']),
          currentIndex: data['currentIndex'],
        );
        //print("created event object with state: ${_playbackEvent.state}");
        return _playbackEvent;
      } catch (e, stacktrace) {
        print("Error parsing event: $e");
        print("$stacktrace");
        rethrow;
      }
    });
    _eventChannelStreamSubscription = _eventChannelStream.listen(
      _playbackEventSubject.add,
      onError: _playbackEventSubject.addError,
    );
    _processingStateSubject.addStream(playbackEventStream
        .map((event) => event.processingState)
        .distinct()
        .handleError((err, stack) {/* noop */}));
    _bufferedPositionSubject.addStream(playbackEventStream
        .map((event) => event.bufferedPosition)
        .distinct()
        .handleError((err, stack) {/* noop */}));
    _icyMetadataSubject.addStream(playbackEventStream
        .map((event) => event.icyMetadata)
        .distinct()
        .handleError((err, stack) {/* noop */}));
    _currentIndexSubject.addStream(playbackEventStream
        .map((event) => event.currentIndex)
        .distinct()
        .handleError((err, stack) {/* noop */}));
    _playerStateSubject.addStream(
        Rx.combineLatest2<bool, PlaybackEvent, PlayerState>(
                playingStream,
                playbackEventStream,
                (playing, event) => PlayerState(playing, event.processingState))
            .distinct()
            .handleError((err, stack) {/* noop */}));
  }

  /// The latest [PlaybackEvent].
  PlaybackEvent get playbackEvent => _playbackEvent;

  /// A stream of [PlaybackEvent]s.
  Stream<PlaybackEvent> get playbackEventStream => _playbackEventSubject.stream;

  /// The duration of the current audio or null if unknown.
  Duration get duration => _playbackEvent.duration;

  /// The duration of the current audio or null if unknown.
  Future<Duration> get durationFuture => _durationFuture;

  /// The duration of the current audio.
  Stream<Duration> get durationStream => _durationSubject.stream;

  /// The current [ProcessingState].
  ProcessingState get processingState => _playbackEvent.processingState;

  /// A stream of [ProcessingState]s.
  Stream<ProcessingState> get processingStateStream =>
      _processingStateSubject.stream;

  /// Whether the player is playing.
  bool get playing => _playingSubject.value;

  /// A stream of changing [playing] states.
  Stream<bool> get playingStream => _playingSubject.stream;

  /// The current volume of the player.
  double get volume => _volumeSubject.value;

  /// A stream of [volume] changes.
  Stream<double> get volumeStream => _volumeSubject.stream;

  /// The current speed of the player.
  double get speed => _speedSubject.value;

  /// A stream of current speed values.
  Stream<double> get speedStream => _speedSubject.stream;

  /// The position up to which buffered audio is available.
  Duration get bufferedPosition => _bufferedPositionSubject.value;

  /// A stream of buffered positions.
  Stream<Duration> get bufferedPositionStream =>
      _bufferedPositionSubject.stream;

  /// The latest ICY metadata received through the audio source.
  IcyMetadata get icyMetadata => _playbackEvent.icyMetadata;

  /// A stream of ICY metadata received through the audio source.
  Stream<IcyMetadata> get icyMetadataStream => _icyMetadataSubject.stream;

  /// The current player state containing only the processing and playing
  /// states.
  PlayerState get playerState => _playerStateSubject.value;

  /// A stream of [PlayerState]s.
  Stream<PlayerState> get playerStateStream => _playerStateSubject.stream;

  /// The index of the current item.
  int get currentIndex => _currentIndexSubject.value;

  /// A stream broadcasting the current item.
  Stream<int> get currentIndexStream => _currentIndexSubject.stream;

  /// Whether there is another item after the current index.
  bool get hasNext =>
      _audioSource != null &&
      currentIndex != null &&
      currentIndex + 1 < _audioSource.sequence.length;

  /// Whether there is another item before the current index.
  bool get hasPrevious =>
      _audioSource != null && currentIndex != null && currentIndex > 0;

  /// The current loop mode.
  LoopMode get loopMode => _loopModeSubject.value;

  /// A stream of [LoopMode]s.
  Stream<LoopMode> get loopModeStream => _loopModeSubject.stream;

  /// Whether shuffle mode is currently enabled.
  bool get shuffleModeEnabled => _shuffleModeEnabledSubject.value;

  /// A stream of the shuffle mode status.
  Stream<bool> get shuffleModeEnabledStream =>
      _shuffleModeEnabledSubject.stream;

  /// Whether the player should automatically delay playback in order to
  /// minimize stalling. (iOS 10.0 or later only)
  bool get automaticallyWaitsToMinimizeStalling =>
      _automaticallyWaitsToMinimizeStalling;

  /// The current position of the player.
  Duration get position {
    if (playing && processingState == ProcessingState.ready) {
      final result = _playbackEvent.updatePosition +
          (DateTime.now().difference(_playbackEvent.updateTime)) * speed;
      return _playbackEvent.duration == null ||
              result <= _playbackEvent.duration
          ? result
          : _playbackEvent.duration;
    } else {
      return _playbackEvent.updatePosition;
    }
  }

  /// A stream tracking the current position of this player, suitable for
  /// animating a seek bar. To ensure a smooth animation, this stream emits
  /// values more frequently on short items where the seek bar moves more
  /// quickly, and less frequenly on long items where the seek bar moves more
  /// slowly. The interval between each update will be no quicker than once
  /// every 16ms and no slower than once every 200ms.
  ///
  /// See [createPositionStream] for more control over the stream parameters.
  Stream<Duration> get positionStream {
    if (_positionSubject == null) {
      _positionSubject = BehaviorSubject<Duration>();
      _positionSubject.addStream(createPositionStream(
          steps: 800,
          minPeriod: Duration(milliseconds: 16),
          maxPeriod: Duration(milliseconds: 200)));
    }
    return _positionSubject.stream;
  }

  /// Creates a new stream periodically tracking the current position of this
  /// player. The stream will aim to emit [steps] position updates from the
  /// beginning to the end of the current audio source, at intervals of
  /// [duration] / [steps]. This interval will be clipped between [minPeriod]
  /// and [maxPeriod]. This stream will not emit values while audio playback is
  /// paused or stalled.
  ///
  /// Note: each time this method is called, a new stream is created. If you
  /// intend to use this stream multiple times, you should hold a reference to
  /// the returned stream and close it once you are done.
  Stream<Duration> createPositionStream({
    int steps = 800,
    Duration minPeriod = const Duration(milliseconds: 200),
    Duration maxPeriod = const Duration(milliseconds: 200),
  }) {
    assert(minPeriod <= maxPeriod);
    assert(minPeriod > Duration.zero);
    Duration duration() => this.duration ?? Duration.zero;
    Duration step() {
      var s = duration() ~/ steps;
      if (s < minPeriod) s = minPeriod;
      if (s > maxPeriod) s = maxPeriod;
      return s;
    }

    StreamController<Duration> controller = StreamController.broadcast();
    Timer currentTimer;
    StreamSubscription durationSubscription;
    StreamSubscription playbackEventSubscription;
    void yieldPosition(Timer timer) {
      if (controller.isClosed) {
        timer.cancel();
        durationSubscription?.cancel();
        playbackEventSubscription?.cancel();
        return;
      }
      if (_durationSubject.isClosed) {
        timer.cancel();
        durationSubscription?.cancel();
        playbackEventSubscription?.cancel();
        controller.close();
        return;
      }
      controller.add(position);
    }

    currentTimer = Timer.periodic(step(), yieldPosition);
    durationSubscription = durationStream.listen((duration) {
      currentTimer.cancel();
      currentTimer = Timer.periodic(step(), yieldPosition);
    });
    playbackEventSubscription = playbackEventStream.listen((event) {
      controller.add(position);
    });
    return controller.stream.distinct();
  }

  /// Convenience method to load audio from a URL with optional headers,
  /// equivalent to:
  ///
  /// ```
  /// load(AudioSource.uri(Uri.parse(url), headers: headers));
  /// ```
  ///
  ///
  Future<Duration> setUrl(String url, {Map headers}) =>
      load(AudioSource.uri(Uri.parse(url), headers: headers));

  /// Convenience method to load audio from a file, equivalent to:
  ///
  /// ```
  /// load(AudioSource.uri(Uri.file(filePath)));
  /// ```
  Future<Duration> setFilePath(String filePath) =>
      load(AudioSource.uri(Uri.file(filePath)));

  /// Convenience method to load audio from an asset, equivalent to:
  ///
  /// ```
  /// load(AudioSource.uri(Uri.parse('asset://$filePath')));
  /// ```
  Future<Duration> setAsset(String assetPath) =>
      load(AudioSource.uri(Uri.parse('asset://$assetPath')));

  /// Loads audio from an [AudioSource] and completes when the audio is ready
  /// to play with the duration of that audio, or null if the duration is unknown.
  ///
  /// This method throws:
  ///
  /// * [PlayerException] if the audio source was unable to be loaded.
  /// * [PlayerInterruptedException] if another call to [load] happened before
  /// this call completed.
  Future<Duration> load(AudioSource source) async {
    try {
      _audioSource = source;
      final duration = await _load(source);
      // Wait for loading state to pass.
      await processingStateStream
          .firstWhere((state) => state != ProcessingState.loading);
      return duration;
    } catch (e) {
      _audioSource = null;
      _audioSources.clear();
      rethrow;
    }
  }

  _registerAudioSource(AudioSource source) {
    _audioSources[source._id] = source;
  }

  Future<Duration> _load(AudioSource source) async {
    try {
      if (!kIsWeb && source._requiresHeaders) {
        if (_proxy == null) {
          _proxy = _ProxyHttpServer();
          await _proxy.start();
        }
      }
      await source._setup(this);
      _durationFuture = _invokeMethod('load', [source.toJson()]).then(
          (ms) => (ms == null || ms < 0) ? null : Duration(milliseconds: ms));
      final duration = await _durationFuture;
      _durationSubject.add(duration);
      return duration;
    } on PlatformException catch (e) {
      try {
        throw PlayerException(int.parse(e.code), e.message);
      } on FormatException catch (_) {
        if (e.code == 'abort') {
          throw PlayerInterruptedException(e.message);
        } else {
          throw PlayerException(9999999, e.message);
        }
      }
    }
  }

  /// Clips the current [AudioSource] to the given [start] and [end]
  /// timestamps. If [start] is null, it will be reset to the start of the
  /// original [AudioSource]. If [end] is null, it will be reset to the end of
  /// the original [AudioSource]. This method cannot be called from the
  /// [AudioPlaybackState.none] state.
  Future<Duration> setClip({Duration start, Duration end}) async {
    final duration = await _load(start == null && end == null
        ? _audioSource
        : ClippingAudioSource(
            child: _audioSource,
            start: start,
            end: end,
          ));
    // Wait for loading state to pass.
    await processingStateStream
        .firstWhere((state) => state != ProcessingState.loading);
    return duration;
  }

  /// Tells the player to play audio as soon as an audio source is loaded and
  /// ready to play. The [Future] returned by this method completes when the
  /// playback completes or is paused or stopped. If the player is already
  /// playing, this method completes immediately.
  ///
  /// This method causes [playing] to become true, and it will remain true
  /// until [pause] or [stop] is called. This means that if playback completes,
  /// and then you [seek] to an earlier position in the audio, playback will
  /// continue playing from that position. If you instead wish to [pause] or
  /// [stop] playback on completion, you can call either method as soon as
  /// [processingState] becomes [ProcessingState.completed] by listening to
  /// [processingStateStream].
  Future<void> play() async {
    if (playing) return;
    _playingSubject.add(true);
    await _invokeMethod('play');
  }

  /// Pauses the currently playing media. This method does nothing if
  /// ![playing].
  Future<void> pause() async {
    if (!playing) return;
    // Update local state immediately so that queries aren't surprised.
    _playbackEvent = _playbackEvent.copyWith(
      updatePosition: position,
      updateTime: DateTime.now(),
    );
    _playbackEventSubject.add(_playbackEvent);
    _playingSubject.add(false);
    // TODO: perhaps modify platform side to ensure new state is broadcast
    // before this method returns.
    await _invokeMethod('pause');
  }

  /// Convenience method to pause and seek to zero.
  Future<void> stop() async {
    await pause();
    await seek(Duration.zero);
  }

  /// Sets the volume of this player, where 1.0 is normal volume.
  Future<void> setVolume(final double volume) async {
    _volumeSubject.add(volume);
    await _invokeMethod('setVolume', [volume]);
  }

  /// Sets the playback speed of this player, where 1.0 is normal speed.
  Future<void> setSpeed(final double speed) async {
    _playbackEvent = _playbackEvent.copyWith(
      updatePosition: position,
      updateTime: DateTime.now(),
    );
    _playbackEventSubject.add(_playbackEvent);
    _speedSubject.add(speed);
    await _invokeMethod('setSpeed', [speed]);
  }

  /// Sets the [LoopMode]. The gapless looping support is as follows:
  ///
  /// * Android: supported
  /// * iOS/macOS: not supported, however, gapless looping can be achieved by
  /// using [LoopingAudioSource].
  /// * Web: not supported
  Future<void> setLoopMode(LoopMode mode) async {
    _loopModeSubject.add(mode);
    await _invokeMethod('setLoopMode', [mode.index]);
  }

  /// Sets whether shuffle mode is enabled.
  Future<void> setShuffleModeEnabled(bool enabled) async {
    _shuffleModeEnabledSubject.add(enabled);
    await _invokeMethod('setShuffleModeEnabled', [enabled]);
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

  /// Seeks to a particular [position]. If a composition of multiple
  /// [AudioSource]s has been loaded, you may also specify [index] to seek to a
  /// particular item within that sequence. This method has no effect unless
  /// an audio source has been loaded.
  Future<void> seek(final Duration position, {int index}) async {
    switch (processingState) {
      case ProcessingState.none:
      case ProcessingState.loading:
        return;
      default:
        _playbackEvent = _playbackEvent.copyWith(
          updatePosition: position,
          updateTime: DateTime.now(),
        );
        _playbackEventSubject.add(_playbackEvent);
        await _invokeMethod('seek', [position?.inMilliseconds, index]);
    }
  }

  /// Seek to the next item.
  Future<void> seekToNext() async {
    if (hasNext) {
      await seek(Duration.zero, index: currentIndex + 1);
    }
  }

  /// Seek to the previous item.
  Future<void> seekToPrevious() async {
    if (hasPrevious) {
      await seek(Duration.zero, index: currentIndex - 1);
    }
  }

  /// Release all resources associated with this player. You must invoke this
  /// after you are done with the player.
  Future<void> dispose() async {
    await _invokeMethod('dispose');
    _audioSource = null;
    _audioSources.values.forEach((s) => s._dispose());
    _audioSources.clear();
    _proxy?.stop();
    await _durationSubject.close();
    await _eventChannelStreamSubscription.cancel();
    await _loopModeSubject.close();
    await _shuffleModeEnabledSubject.close();
    await _playingSubject.close();
    await _volumeSubject.close();
    await _speedSubject.close();
    if (_positionSubject != null) {
      await _positionSubject.close();
    }
  }

  Future<dynamic> _invokeMethod(String method, [dynamic args]) async =>
      (await _channel).invokeMethod(method, args);
}

/// Captures the details of any error accessing, loading or playing an audio
/// source, including an invalid or inaccessible URL, or an audio encoding that
/// could not be understood.
class PlayerException {
  /// On iOS and macOS, maps to `NSError.code`. On Android, maps to
  /// `ExoPlaybackException.type`. On Web, maps to `MediaError.code`.
  final int code;

  /// On iOS and macOS, maps to `NSError.localizedDescription`. On Android,
  /// maps to `ExoPlaybackException.getMessage()`. On Web, a generic message
  /// is provided.
  final String message;

  PlayerException(this.code, this.message);

  @override
  String toString() => "($code) $message";
}

/// An error that occurs when one operation on the player has been interrupted
/// (e.g. by another simultaneous operation).
class PlayerInterruptedException {
  final String message;

  PlayerInterruptedException(this.message);

  @override
  String toString() => "$message";
}

/// Encapsulates the playback state and current position of the player.
class PlaybackEvent {
  /// The current processing state.
  final ProcessingState processingState;

  /// When the last time a position discontinuity happened, as measured in time
  /// since the epoch.
  final DateTime updateTime;

  /// The position at [updateTime].
  final Duration updatePosition;

  /// The buffer position.
  final Duration bufferedPosition;

  /// The media duration, or null if unknown.
  final Duration duration;

  /// The latest ICY metadata received through the audio stream.
  final IcyMetadata icyMetadata;

  /// The index of the currently playing item.
  final int currentIndex;

  PlaybackEvent({
    @required this.processingState,
    @required this.updateTime,
    @required this.updatePosition,
    @required this.bufferedPosition,
    @required this.duration,
    @required this.icyMetadata,
    @required this.currentIndex,
  });

  PlaybackEvent copyWith({
    ProcessingState processingState,
    DateTime updateTime,
    Duration updatePosition,
    Duration bufferedPosition,
    double speed,
    Duration duration,
    IcyMetadata icyMetadata,
    UriAudioSource currentIndex,
  }) =>
      PlaybackEvent(
        processingState: processingState ?? this.processingState,
        updateTime: updateTime ?? this.updateTime,
        updatePosition: updatePosition ?? this.updatePosition,
        bufferedPosition: bufferedPosition ?? this.bufferedPosition,
        duration: duration ?? this.duration,
        icyMetadata: icyMetadata ?? this.icyMetadata,
        currentIndex: currentIndex ?? this.currentIndex,
      );

  @override
  String toString() =>
      "{processingState=$processingState, updateTime=$updateTime, updatePosition=$updatePosition}";
}

/// Enumerates the different processing states of a player.
enum ProcessingState {
  /// The player has not loaded an [AudioSource].
  none,

  /// The player is loading an [AudioSource].
  loading,

  /// The player is buffering audio and unable to play.
  buffering,

  /// The player is has enough audio buffered and is able to play.
  ready,

  /// The player has reached the end of the audio.
  completed,
}

/// Encapsulates the playing and processing states. These two states vary
/// orthogonally, and so if [processingState] is [ProcessingState.buffering],
/// you can check [playing] to determine whether the buffering occurred while
/// the player was playing or while the player was paused.
class PlayerState {
  /// Whether the player will play when [processingState] is
  /// [ProcessingState.ready].
  final bool playing;

  /// The current processing state of the player.
  final ProcessingState processingState;

  PlayerState(this.playing, this.processingState);

  @override
  String toString() => 'playing=$playing,processingState=$processingState';

  @override
  int get hashCode => toString().hashCode;

  @override
  bool operator ==(dynamic other) =>
      other is PlayerState &&
      other?.playing == playing &&
      other?.processingState == processingState;
}

class IcyInfo {
  final String title;
  final String url;

  IcyInfo({@required this.title, @required this.url});

  IcyInfo.fromJson(Map json) : this(title: json['title'], url: json['url']);

  @override
  String toString() => 'title=$title,url=$url';

  @override
  int get hashCode => toString().hashCode;

  @override
  bool operator ==(dynamic other) =>
      other is IcyInfo && other?.toString() == toString();
}

class IcyHeaders {
  final int bitrate;
  final String genre;
  final String name;
  final int metadataInterval;
  final String url;
  final bool isPublic;

  IcyHeaders({
    @required this.bitrate,
    @required this.genre,
    @required this.name,
    @required this.metadataInterval,
    @required this.url,
    @required this.isPublic,
  });

  IcyHeaders.fromJson(Map json)
      : this(
          bitrate: json['bitrate'],
          genre: json['genre'],
          name: json['name'],
          metadataInterval: json['metadataInterval'],
          url: json['url'],
          isPublic: json['isPublic'],
        );

  @override
  String toString() =>
      'bitrate=$bitrate,genre=$genre,name=$name,metadataInterval=$metadataInterval,url=$url,isPublic=$isPublic';

  @override
  int get hashCode => toString().hashCode;

  @override
  bool operator ==(dynamic other) =>
      other is IcyHeaders && other?.toString() == toString();
}

class IcyMetadata {
  final IcyInfo info;
  final IcyHeaders headers;

  IcyMetadata({@required this.info, @required this.headers});

  IcyMetadata.fromJson(Map json)
      : this(info: json['info'], headers: json['headers']);

  @override
  int get hashCode => info.hashCode ^ headers.hashCode;

  @override
  bool operator ==(dynamic other) =>
      other is IcyMetadata && other?.info == info && other?.headers == headers;
}

/// The audio session categories on iOS, to be used with
/// [AudioPlayer.setIosCategory].
enum IosCategory {
  ambient,
  soloAmbient,
  playback,
  record,
  playAndRecord,
  multiRoute,
}

/// A local proxy HTTP server for making remote GET requests with headers.
///
/// TODO: Recursively attach headers to items in playlists like m3u8.
class _ProxyHttpServer {
  HttpServer _server;

  /// Maps request keys to [_ProxyRequest]s.
  final Map<String, _ProxyRequest> _uriMap = {};

  /// The port this server is bound to on localhost. This is set only after
  /// [start] has completed.
  int get port => _server.port;

  /// Associate headers with a URL. This may be called only after [start] has
  /// completed.
  Uri addUrl(Uri url, Map<String, String> headers) {
    final path = _requestKey(url);
    _uriMap[path] = _ProxyRequest(url, headers);
    return url.replace(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: port,
    );
  }

  /// A unique key for each request that can be processed by this proxy,
  /// made up of the URL path and query string. It is not possible to
  /// simultaneously track requests that have the same URL path and query
  /// but differ in other respects such as the port or headers.
  String _requestKey(Uri uri) => '${uri.path}?${uri.query}';

  /// Starts the server.
  Future start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      if (request.method == 'GET') {
        final path = _requestKey(request.uri);
        final proxyRequest = _uriMap[path];
        final originRequest = await HttpClient().getUrl(proxyRequest.uri);

        // Rewrite request headers
        final host = originRequest.headers.value('host');
        originRequest.headers.clear();
        request.headers.forEach((name, value) {
          originRequest.headers.set(name, value);
        });
        for (var name in proxyRequest.headers.keys) {
          originRequest.headers.set(name, proxyRequest.headers[name]);
        }
        originRequest.headers.set('host', host);

        // Try to make normal request
        try {
          final originResponse = await originRequest.close();

          request.response.headers.clear();
          originResponse.headers.forEach((name, value) {
            request.response.headers.set(name, value);
          });

          // Pipe response
          await originResponse.pipe(request.response);
        } on HttpException {
          // We likely are dealing with a streaming protocol
          if (proxyRequest.uri.scheme == 'http') {
            // Try parsing HTTP 0.9 response
            //request.response.headers.clear();
            final socket = await Socket.connect(
                proxyRequest.uri.host, proxyRequest.uri.port);
            final clientSocket =
                await request.response.detachSocket(writeHeaders: false);
            Completer done = Completer();
            socket.listen(
              clientSocket.add,
              onDone: () async {
                await clientSocket.flush();
                socket.close();
                clientSocket.close();
                done.complete();
              },
            );
            // Rewrite headers
            final headers = <String, String>{};
            request.headers.forEach((name, value) {
              if (name.toLowerCase() != 'host') {
                headers[name] = value.join(",");
              }
            });
            for (var name in proxyRequest.headers.keys) {
              headers[name] = proxyRequest.headers[name];
            }
            socket.write("GET ${proxyRequest.uri.path} HTTP/1.1\n");
            if (host != null) {
              socket.write("Host: $host\n");
            }
            for (var name in headers.keys) {
              socket.write("$name: ${headers[name]}\n");
            }
            socket.write("\n");
            await socket.flush();
            await done.future;
          }
        }
      }
    });
  }

  /// Stops the server
  Future stop() => _server.close();
}

/// A request for a URL and headers made by a [_ProxyHttpServer].
class _ProxyRequest {
  final Uri uri;
  final Map<String, String> headers;

  _ProxyRequest(this.uri, this.headers);
}

/// Specifies a source of audio to be played. Audio sources are composable
/// using the subclasses of this class. The same [AudioSource] instance should
/// not be used simultaneously by more than one [AudioPlayer].
abstract class AudioSource {
  final String _id;
  AudioPlayer _player;

  /// Creates an [AudioSource] from a [Uri] with optional headers by
  /// attempting to guess the type of stream. On iOS, this uses Apple's SDK to
  /// automatically detect the stream type. On Android, the type of stream will
  /// be guessed from the extension.
  ///
  /// If you are loading DASH or HLS streams that do not have standard "mpd" or
  /// "m3u8" extensions in their URIs, this method will fail to detect the
  /// stream type on Android. If you know in advance what type of audio stream
  /// it is, you should instantiate [DashAudioSource] or [HlsAudioSource]
  /// directly.
  static AudioSource uri(Uri uri, {Map headers, Object tag}) {
    bool hasExtension(Uri uri, String extension) =>
        uri.path.toLowerCase().endsWith('.$extension') ||
        uri.fragment.toLowerCase().endsWith('.$extension');
    if (hasExtension(uri, 'mpd')) {
      return DashAudioSource(uri, headers: headers, tag: tag);
    } else if (hasExtension(uri, 'm3u8')) {
      return HlsAudioSource(uri, headers: headers, tag: tag);
    } else {
      return ProgressiveAudioSource(uri, headers: headers, tag: tag);
    }
  }

  static AudioSource fromJson(Map json) {
    switch (json['type']) {
      case 'progressive':
        return ProgressiveAudioSource(Uri.parse(json['uri']),
            headers: json['headers']);
      case "dash":
        return DashAudioSource(Uri.parse(json['uri']),
            headers: json['headers']);
      case "hls":
        return HlsAudioSource(Uri.parse(json['uri']), headers: json['headers']);
      case "concatenating":
        return ConcatenatingAudioSource(
            children: (json['audioSources'] as List)
                .map((s) => AudioSource.fromJson(s))
                .toList());
      case "clipping":
        return ClippingAudioSource(
            child: AudioSource.fromJson(json['audioSource']),
            start: Duration(milliseconds: json['start']),
            end: Duration(milliseconds: json['end']));
      default:
        throw Exception("Unknown AudioSource type: " + json['type']);
    }
  }

  AudioSource() : _id = _uuid.v4();

  @mustCallSuper
  Future<void> _setup(AudioPlayer player) async {
    _player = player;
    player._registerAudioSource(this);
  }

  @mustCallSuper
  void _dispose() {
    _player = null;
  }

  bool get _requiresHeaders;

  List<IndexedAudioSource> get sequence;

  Map toJson();

  @override
  int get hashCode => _id.hashCode;

  @override
  bool operator ==(dynamic other) => other is AudioSource && other._id == _id;
}

/// An [AudioSource] that can appear in a sequence.
abstract class IndexedAudioSource extends AudioSource {
  final Object tag;

  IndexedAudioSource(this.tag);

  @override
  List<IndexedAudioSource> get sequence => [this];
}

/// An abstract class representing audio sources that are loaded from a URI.
abstract class UriAudioSource extends IndexedAudioSource {
  final Uri uri;
  final Map headers;
  final String _type;
  Uri _overrideUri;
  File _cacheFile;

  UriAudioSource(this.uri, {this.headers, Object tag, @required String type})
      : _type = type,
        super(tag);

  @override
  Future<void> _setup(AudioPlayer player) async {
    await super._setup(player);
    if (uri.scheme == 'asset') {
      _overrideUri = Uri.file((await _loadAsset(uri.path)).path);
    } else if (headers != null) {
      _overrideUri = player._proxy.addUrl(uri, headers);
    }
  }

  @override
  void _dispose() {
    if (_cacheFile?.existsSync() == true) {
      _cacheFile?.deleteSync();
    }
    super._dispose();
  }

  Future<File> _loadAsset(String assetPath) async {
    final file = await _getCacheFile(assetPath);
    this._cacheFile = file;
    if (!file.existsSync()) {
      await file.create(recursive: true);
      await file.writeAsBytes(
          (await rootBundle.load(assetPath)).buffer.asUint8List());
    }
    return file;
  }

  /// Get file for caching asset media with proper extension
  Future<File> _getCacheFile(final String assetPath) async => File(p.join(
      (await getTemporaryDirectory()).path,
      'just_audio_asset_cache',
      '${_player._id}_$_id${p.extension(assetPath)}'));

  @override
  bool get _requiresHeaders => headers != null;

  @override
  Map toJson() => {
        'id': _id,
        'type': _type,
        'uri': (_overrideUri ?? uri).toString(),
        'headers': headers,
      };
}

/// An [AudioSource] representing a regular media file such asn an MP3 or M4A
/// file. The following URI schemes are supported:
///
/// * file: loads from a local file (provided you give your app permission to
/// access that file).
/// * asset: loads from a Flutter asset (not supported on Web).
/// * http(s): loads from an HTTP(S) resource.
///
/// On platforms except for the web, the supplied [headers] will be passed with
/// the HTTP(S) request.
class ProgressiveAudioSource extends UriAudioSource {
  ProgressiveAudioSource(Uri uri, {Map headers, Object tag})
      : super(uri, headers: headers, tag: tag, type: 'progressive');
}

/// An [AudioSource] representing a DASH stream.
///
/// On platforms except for the web, the supplied [headers] will be passed with
/// the HTTP(S) request. Currently headers are not recursively applied to items
/// the HTTP(S) request. Currently headers are not applied recursively.
class DashAudioSource extends UriAudioSource {
  DashAudioSource(Uri uri, {Map headers, Object tag})
      : super(uri, headers: headers, tag: tag, type: 'dash');
}

/// An [AudioSource] representing an HLS stream.
///
/// On platforms except for the web, the supplied [headers] will be passed with
/// the HTTP(S) request. Currently headers are not applied recursively.
class HlsAudioSource extends UriAudioSource {
  HlsAudioSource(Uri uri, {Map headers, Object tag})
      : super(uri, headers: headers, tag: tag, type: 'hls');
}

/// An [AudioSource] representing a concatenation of multiple audio sources to
/// be played in succession. This can be used to create playlists. Playback
/// between items will be gapless on Android, iOS and macOS, while there will
/// be a slight gap on Web.
///
/// (Untested) Audio sources can be dynamically added, removed and reordered
/// while the audio is playing.
class ConcatenatingAudioSource extends AudioSource {
  final List<AudioSource> children;
  final bool useLazyPreparation;

  ConcatenatingAudioSource({
    @required this.children,
    this.useLazyPreparation = false,
  });

  @override
  Future<void> _setup(AudioPlayer player) async {
    await super._setup(player);
    for (var source in children) {
      await source._setup(player);
    }
  }

  /// (Untested) Appends an [AudioSource].
  Future<void> add(AudioSource audioSource) async {
    children.add(audioSource);
    if (_player != null) {
      await _player
          ._invokeMethod('concatenating.add', [_id, audioSource.toJson()]);
    }
  }

  /// (Untested) Inserts an [AudioSource] at [index].
  Future<void> insert(int index, AudioSource audioSource) async {
    children.insert(index, audioSource);
    if (_player != null) {
      await _player._invokeMethod(
          'concatenating.insert', [_id, index, audioSource.toJson()]);
    }
  }

  /// (Untested) Appends multiple [AudioSource]s.
  Future<void> addAll(List<AudioSource> children) async {
    this.children.addAll(children);
    if (_player != null) {
      await _player._invokeMethod('concatenating.addAll',
          [_id, children.map((s) => s.toJson()).toList()]);
    }
  }

  /// (Untested) Insert multiple [AudioSource]s at [index].
  Future<void> insertAll(int index, List<AudioSource> children) async {
    this.children.insertAll(index, children);
    if (_player != null) {
      await _player._invokeMethod('concatenating.insertAll',
          [_id, index, children.map((s) => s.toJson()).toList()]);
    }
  }

  /// (Untested) Dynmaically remove an [AudioSource] at [index] after this
  /// [ConcatenatingAudioSource] has already been loaded.
  Future<void> removeAt(int index) async {
    children.removeAt(index);
    if (_player != null) {
      await _player._invokeMethod('concatenating.removeAt', [_id, index]);
    }
  }

  /// (Untested) Removes a range of [AudioSource]s from index [start] inclusive
  /// to [end] exclusive.
  Future<void> removeRange(int start, int end) async {
    children.removeRange(start, end);
    if (_player != null) {
      await _player
          ._invokeMethod('concatenating.removeRange', [_id, start, end]);
    }
  }

  /// (Untested) Moves an [AudioSource] from [currentIndex] to [newIndex].
  Future<void> move(int currentIndex, int newIndex) async {
    children.insert(newIndex, children.removeAt(currentIndex));
    if (_player != null) {
      await _player
          ._invokeMethod('concatenating.move', [_id, currentIndex, newIndex]);
    }
  }

  /// (Untested) Removes all [AudioSources].
  Future<void> clear() async {
    children.clear();
    if (_player != null) {
      await _player._invokeMethod('concatenating.clear', [_id]);
    }
  }

  /// The number of [AudioSource]s.
  int get length => children.length;

  operator [](int index) => children[index];

  @override
  List<IndexedAudioSource> get sequence =>
      children.expand((s) => s.sequence).toList();

  @override
  bool get _requiresHeaders =>
      children.any((source) => source._requiresHeaders);

  @override
  Map toJson() => {
        'id': _id,
        'type': 'concatenating',
        'audioSources': children.map((source) => source.toJson()).toList(),
        'useLazyPreparation': useLazyPreparation,
      };
}

/// An [AudioSource] that clips the audio of a [UriAudioSource] between a
/// certain start and end time.
class ClippingAudioSource extends IndexedAudioSource {
  final UriAudioSource child;
  final Duration start;
  final Duration end;

  /// Creates an audio source that clips [child] to the range [start]..[end],
  /// where [start] and [end] default to the beginning and end of the original
  /// [child] source.
  ClippingAudioSource({
    @required this.child,
    this.start,
    this.end,
    Object tag,
  }) : super(tag);

  @override
  Future<void> _setup(AudioPlayer player) async {
    await super._setup(player);
    await child._setup(player);
  }

  @override
  bool get _requiresHeaders => child._requiresHeaders;

  @override
  Map toJson() => {
        'id': _id,
        'type': 'clipping',
        'audioSource': child.toJson(),
        'start': start?.inMilliseconds,
        'end': end?.inMilliseconds,
      };
}

// An [AudioSource] that loops a nested [AudioSource] a finite number of times.
// NOTE: this can be inefficient when using a large loop count. If you wish to
// loop an infinite number of times, use [AudioPlayer.setLoopMode].
//
// On iOS and macOS, note that [LoopingAudioSource] will provide gapless
// playback while [AudioPlayer.setLoopMode] will not. (This will be supported
// in a future release.)
class LoopingAudioSource extends AudioSource {
  AudioSource child;
  final int count;

  LoopingAudioSource({
    @required this.child,
    this.count,
  }) : super();

  @override
  List<IndexedAudioSource> get sequence =>
      List.generate(count, (i) => child).expand((s) => s.sequence).toList();

  @override
  bool get _requiresHeaders => child._requiresHeaders;

  @override
  Map toJson() => {
        'id': _id,
        'type': 'looping',
        'audioSource': child.toJson(),
        'count': count,
      };
}

enum LoopMode { off, one, all }
