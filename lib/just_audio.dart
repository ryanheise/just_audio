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
/// * [AudioPlaybackState.stopped]: eventually after [load] completes, and
/// immediately after [stop].
/// * [AudioPlaybackState.paused]: after [pause].
/// * [AudioPlaybackState.playing]: after [play].
/// * [AudioPlaybackState.connecting]: immediately after [load] while waiting
/// for the media to load.
/// * [AudioPlaybackState.completed]: immediately after playback reaches the
/// end of the media or the end of the clip.
///
/// Additionally, after a [seek] request completes, the state will return to
/// whatever state the player was in prior to the seek request.
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

  _ProxyHttpServer _proxy;

  final String _id;

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
    duration: null,
    icyMetadata: null,
    currentIndex: null,
  );

  Stream<AudioPlaybackEvent> _eventChannelStream;

  StreamSubscription<AudioPlaybackEvent> _eventChannelStreamSubscription;

  final _playbackEventSubject = BehaviorSubject<AudioPlaybackEvent>();

  final _playbackStateSubject = BehaviorSubject<AudioPlaybackState>();

  final _bufferingSubject = BehaviorSubject<bool>();

  final _bufferedPositionSubject = BehaviorSubject<Duration>();

  final _icyMetadataSubject = BehaviorSubject<IcyMetadata>();

  final _fullPlaybackStateSubject = BehaviorSubject<FullAudioPlaybackState>();

  final _currentIndexSubject = BehaviorSubject<int>();

  final _loopModeSubject = BehaviorSubject<LoopMode>();

  final _shuffleModeEnabledSubject = BehaviorSubject<bool>();

  double _volume = 1.0;

  double _speed = 1.0;

  bool _automaticallyWaitsToMinimizeStalling = true;

  AudioSource _audioSource;

  Map<String, AudioSource> _audioSources = {};

  /// Creates an [AudioPlayer].
  factory AudioPlayer() => AudioPlayer._internal(_uuid.v4());

  AudioPlayer._internal(this._id) : _channel = _init(_id) {
    _eventChannelStream = EventChannel('com.ryanheise.just_audio.events.$_id')
        .receiveBroadcastStream()
        .map((data) {
      try {
        //print("received raw event: $data");
        final duration = (data['duration'] ?? -1) < 0
            ? null
            : Duration(milliseconds: data['duration']);
        _durationFuture = Future.value(duration);
        _durationSubject.add(duration);
        _audioPlaybackEvent = AudioPlaybackEvent(
          state: AudioPlaybackState.values[data['state']],
          buffering: data['buffering'],
          updatePosition: Duration(milliseconds: data['updatePosition']),
          updateTime: Duration(milliseconds: data['updateTime']),
          bufferedPosition: Duration(milliseconds: data['bufferedPosition']),
          speed: _speed,
          duration: duration,
          icyMetadata: data['icyMetadata'] == null
              ? null
              : IcyMetadata.fromJson(data['icyMetadata']),
          currentIndex: data['currentIndex'],
        );
        //print("created event object with state: ${_audioPlaybackEvent.state}");
        return _audioPlaybackEvent;
      } catch (e, stacktrace) {
        print("Error parsing event: $e");
        print("$stacktrace");
        rethrow;
      }
    });
    _eventChannelStreamSubscription = _eventChannelStream.listen(
        _playbackEventSubject.add,
        onError: _playbackEventSubject.addError);
    _playbackStateSubject.addStream(playbackEventStream
        .map((state) => state.state)
        .distinct()
        .handleError((err, stack) {/* noop */}));
    _bufferingSubject.addStream(playbackEventStream
        .map((state) => state.buffering)
        .distinct()
        .handleError((err, stack) {/* noop */}));
    _bufferedPositionSubject.addStream(playbackEventStream
        .map((state) => state.bufferedPosition)
        .distinct()
        .handleError((err, stack) {/* noop */}));
    _icyMetadataSubject.addStream(playbackEventStream
        .map((state) => state.icyMetadata)
        .distinct()
        .handleError((err, stack) {/* noop */}));
    _currentIndexSubject.addStream(playbackEventStream
        .map((state) => state.currentIndex)
        .distinct()
        .handleError((err, stack) {/* noop */}));
    _fullPlaybackStateSubject.addStream(playbackEventStream
        .map((event) => FullAudioPlaybackState(
            event.state, event.buffering, event.icyMetadata))
        .distinct()
        .handleError((err, stack) {/* noop */}));
  }

  /// The duration of any media loaded via [load], or null if unknown.
  Future<Duration> get durationFuture => _durationFuture;

  /// The duration of any media loaded via [load].
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

  /// A stream broadcasting the current item.
  Stream<int> get currentIndexStream => _currentIndexSubject.stream;

  /// Whether the player is buffering.
  bool get buffering => _audioPlaybackEvent.buffering;

  /// The current position of the player.
  Duration get position => _audioPlaybackEvent.position;

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

  /// A stream of [LoopMode]s.
  Stream<LoopMode> get loopModeStream => _loopModeSubject.stream;

  /// A stream of the shuffle mode status.
  Stream<bool> get shuffleModeEnabledStream =>
      _shuffleModeEnabledSubject.stream;

  /// The current volume of the player.
  double get volume => _volume;

  /// The current speed of the player.
  double get speed => _speed;

  /// Whether the player should automatically delay playback in order to
  /// minimize stalling. (iOS 10.0 or later only)
  bool get automaticallyWaitsToMinimizeStalling =>
      _automaticallyWaitsToMinimizeStalling;

  /// Convenience method to load audio from a URL with optional headers,
  /// equivalent to:
  ///
  /// ```
  /// load(ProgressiveAudioSource(Uri.parse(url), headers: headers));
  /// ```
  ///
  ///
  Future<Duration> setUrl(String url, {Map headers}) =>
      load(AudioSource.uri(Uri.parse(url), headers: headers));

  /// Convenience method to load audio from a file, equivalent to:
  ///
  /// ```
  /// load(ProgressiveAudioSource(Uri.file(filePath)));
  /// ```
  Future<Duration> setFilePath(String filePath) =>
      load(ProgressiveAudioSource(Uri.file(filePath)));

  /// Convenience method to load audio from an asset, equivalent to:
  ///
  /// ```
  /// load(ProgressiveAudioSource(Uri.parse('asset://$filePath')));
  /// ```
  Future<Duration> setAsset(String assetPath) =>
      load(ProgressiveAudioSource(Uri.parse('asset://$assetPath')));

  /// Loads audio from an [AudioSource] and completes with the duration of that
  /// audio, or an exception if this call was interrupted by another
  /// call to [load], or if for any reason the audio source was unable to be
  /// loaded.
  ///
  /// If the duration is unknown, null will be returned.
  ///
  /// On Android, DASH and HLS streams are detected only when the URL's path
  /// has an "mpd" or "m3u8" extension. If the URL does not have such an
  /// extension and you have no control over the server, and you also know the
  /// type of the stream in advance, you may as a workaround supply the
  /// extension as a URL fragment. e.g.
  /// https://somewhere.com/somestream?x=etc#.m3u8
  Future<Duration> load(AudioSource source) async {
    try {
      _audioSource = source;
      return await _load(source);
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
      // TODO: Create own exception type.
      throw Exception(e.message);
    }
  }

  /// Clips the current [AudioSource] to the given [start] and [end]
  /// timestamps. If [start] is null, it will be reset to the start of the
  /// original [AudioSource]. If [end] is null, it will be reset to the end of
  /// the original [AudioSource]. This method cannot be called from the
  /// [AudioPlaybackState.none] state.
  Future<Duration> setClip({Duration start, Duration end}) =>
      _load(start == null && end == null
          ? _audioSource
          : ClippingAudioSource(
              audioSource: _audioSource,
              start: start,
              end: end,
            ));

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

  /// Sets the [LoopMode].
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
  /// particular item within that sequence. It is legal to invoke this method
  /// from any state except for [AudioPlaybackState.none] and
  /// [AudioPlaybackState.connecting].
  Future<void> seek(final Duration position, {int index}) async {
    await _invokeMethod('seek', [position?.inMilliseconds, index]);
  }

  /// Release all resources associated with this player. You must invoke this
  /// after you are done with the player. This method can be invoked from any
  /// state except for:
  ///
  /// * [AudioPlaybackState.none]
  /// * [AudioPlaybackState.connecting]
  Future<void> dispose() async {
    await _invokeMethod('dispose');
    _audioSource = null;
    _audioSources.values.forEach((s) => s._dispose());
    _audioSources.clear();
    _proxy?.stop();
    await _durationSubject.close();
    await _eventChannelStreamSubscription.cancel();
    await _playbackEventSubject.close();
    await _loopModeSubject.close();
    await _shuffleModeEnabledSubject.close();
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

  /// The media duration, or null if unknown.
  final Duration duration;

  final IcyMetadata icyMetadata;

  /// The index of the currently playing item.
  final int currentIndex;

  AudioPlaybackEvent({
    @required this.state,
    @required this.buffering,
    @required this.updateTime,
    @required this.updatePosition,
    @required this.bufferedPosition,
    @required this.speed,
    @required this.duration,
    @required this.icyMetadata,
    @required this.currentIndex,
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
    UriAudioSource currentIndex,
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
        currentIndex: currentIndex ?? this.currentIndex,
      );

  /// The current position of the player.
  Duration get position {
    if (state == AudioPlaybackState.playing && !buffering) {
      final result = updatePosition +
          (Duration(milliseconds: DateTime.now().millisecondsSinceEpoch) -
                  updateTime) *
              speed;
      return duration == null || result <= duration ? result : duration;
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

  @override
  int get hashCode =>
      icyMetadata.hashCode * (state.index + 1) * (buffering ? 2 : 1);

  @override
  bool operator ==(dynamic other) =>
      other is FullAudioPlaybackState &&
      other?.state == state &&
      other?.buffering == buffering &&
      other?.icyMetadata == icyMetadata;
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
  static AudioSource uri(Uri uri, {Map headers, Object tag}) {
    bool hasExtension(Uri uri, String extension) =>
        uri.path.toLowerCase().endsWith('.$extension') ||
        uri.fragment.toLowerCase().endsWith('.$extension');
    if (hasExtension(uri, 'mdp')) {
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
            audioSources: (json['audioSources'] as List)
                .map((s) => AudioSource.fromJson(s))
                .toList());
      case "clipping":
        return ClippingAudioSource(
            audioSource: AudioSource.fromJson(json['audioSource']),
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
/// be played in succession. This can be used to create playlists. Audio sources
/// can be dynamically added, removed and reordered while the audio is playing.
class ConcatenatingAudioSource extends AudioSource {
  final List<AudioSource> audioSources;
  final bool useLazyPreparation;

  ConcatenatingAudioSource({
    @required this.audioSources,
    this.useLazyPreparation = false,
  });

  @override
  Future<void> _setup(AudioPlayer player) async {
    await super._setup(player);
    for (var source in audioSources) {
      await source._setup(player);
    }
  }

  /// Appends an [AudioSource].
  Future<void> add(AudioSource audioSource) async {
    audioSources.add(audioSource);
    if (_player != null) {
      await _player
          ._invokeMethod('concatenating.add', [_id, audioSource.toJson()]);
    }
  }

  /// Inserts an [AudioSource] at [index].
  Future<void> insert(int index, AudioSource audioSource) async {
    audioSources.insert(index, audioSource);
    if (_player != null) {
      await _player._invokeMethod(
          'concatenating.insert', [_id, index, audioSource.toJson()]);
    }
  }

  /// Appends multiple [AudioSource]s.
  Future<void> addAll(List<AudioSource> audioSources) async {
    this.audioSources.addAll(audioSources);
    if (_player != null) {
      await _player._invokeMethod('concatenating.addAll',
          [_id, audioSources.map((s) => s.toJson()).toList()]);
    }
  }

  /// Insert multiple [AudioSource]s at [index].
  Future<void> insertAll(int index, List<AudioSource> audioSources) async {
    audioSources.insertAll(index, audioSources);
    if (_player != null) {
      await _player._invokeMethod('concatenating.insertAll',
          [_id, index, audioSources.map((s) => s.toJson()).toList()]);
    }
  }

  /// Dynmaically remove an [AudioSource] at [index] after this
  /// [ConcatenatingAudioSource] has already been loaded.
  Future<void> removeAt(int index) async {
    audioSources.removeAt(index);
    if (_player != null) {
      await _player._invokeMethod('concatenating.removeAt', [_id, index]);
    }
  }

  /// Removes a range of [AudioSource]s from index [start] inclusive to [end]
  /// exclusive.
  Future<void> removeRange(int start, int end) async {
    audioSources.removeRange(start, end);
    if (_player != null) {
      await _player
          ._invokeMethod('concatenating.removeRange', [_id, start, end]);
    }
  }

  /// Moves an [AudioSource] from [currentIndex] to [newIndex].
  Future<void> move(int currentIndex, int newIndex) async {
    audioSources.insert(newIndex, audioSources.removeAt(currentIndex));
    if (_player != null) {
      await _player
          ._invokeMethod('concatenating.move', [_id, currentIndex, newIndex]);
    }
  }

  /// Removes all [AudioSources].
  Future<void> clear() async {
    audioSources.clear();
    if (_player != null) {
      await _player._invokeMethod('concatenating.clear', [_id]);
    }
  }

  /// The number of [AudioSource]s.
  int get length => audioSources.length;

  operator [](int index) => audioSources[index];

  @override
  List<IndexedAudioSource> get sequence =>
      audioSources.expand((s) => s.sequence).toList();

  @override
  bool get _requiresHeaders =>
      audioSources.any((source) => source._requiresHeaders);

  @override
  Map toJson() => {
        'id': _id,
        'type': 'concatenating',
        'audioSources': audioSources.map((source) => source.toJson()).toList(),
        'useLazyPreparation': useLazyPreparation,
      };
}

/// An [AudioSource] that clips the audio of a [UriAudioSource] between a
/// certain start and end time.
class ClippingAudioSource extends IndexedAudioSource {
  final UriAudioSource audioSource;
  final Duration start;
  final Duration end;

  ClippingAudioSource({
    @required this.audioSource,
    this.start,
    this.end,
    Object tag,
  }) : super(tag);

  @override
  Future<void> _setup(AudioPlayer player) async {
    await super._setup(player);
    await audioSource._setup(player);
  }

  @override
  bool get _requiresHeaders => audioSource._requiresHeaders;

  @override
  Map toJson() => {
        'id': _id,
        'type': 'clipping',
        'audioSource': audioSource.toJson(),
        'start': start?.inMilliseconds,
        'end': end?.inMilliseconds,
      };
}

// An [AudioSource] that loops a nested [AudioSource] a
// specified number of times.
class LoopingAudioSource extends AudioSource {
  AudioSource audioSource;
  final int count;

  LoopingAudioSource({
    @required this.audioSource,
    this.count,
  }) : super();

  @override
  List<IndexedAudioSource> get sequence =>
      List.generate(count, (i) => audioSource)
          .expand((s) => s.sequence)
          .toList();

  @override
  bool get _requiresHeaders => audioSource._requiresHeaders;

  @override
  Map toJson() => {
        'id': _id,
        'type': 'looping',
        'audioSource': audioSource.toJson(),
        'count': count,
      };
}

enum LoopMode { off, one, all }
