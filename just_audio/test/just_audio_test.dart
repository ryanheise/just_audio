import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:mockito/mockito.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // We need an actual HttpClient to test the proxy server.
  final overrides = MyHttpOverrides();
  HttpOverrides.global = overrides;
  HttpOverrides.runWithHttpOverrides(runTests, overrides);
}

void runTests() {
  final mock = MockJustAudio();
  JustAudioPlatform.instance = mock;
  final audioSessionChannel = MethodChannel('com.ryanheise.audio_session');

  void expectDuration(Duration a, Duration b, {int epsilon = 200}) {
    expect((a - b).inMilliseconds.abs(), lessThanOrEqualTo(epsilon));
  }

  void expectState({
    AudioPlayer player,
    Duration position,
    ProcessingState processingState,
    bool playing,
  }) {
    if (position != null) {
      expectDuration(player.position, position);
    }
    if (processingState != null) {
      expect(player.processingState, equals(processingState));
    }
    if (playing != null) {
      expect(player.playing, equals(playing));
    }
  }

  void checkIndices(List<int> indices, int length) {
    expect(indices.length, length);
    final sorted = List.of(indices)..sort();
    expect(sorted, equals(List.generate(indices.length, (i) => i)));
  }

  setUp(() {
    audioSessionChannel.setMockMethodCallHandler((MethodCall methodCall) async {
      return null;
    });
  });

  tearDown(() {
    audioSessionChannel.setMockMethodCallHandler(null);
  });

  test('init', () async {
    final player = AudioPlayer();
    expect(player.processingState, equals(ProcessingState.idle));
    expect(player.position, equals(Duration.zero));
    //expect(player.bufferedPosition, equals(Duration.zero));
    expect(player.duration, equals(null));
    expect(player.icyMetadata, equals(null));
    expect(player.currentIndex, equals(null));
    expect(player.androidAudioSessionId, equals(null));
    expect(player.playing, equals(false));
    expect(player.volume, equals(1.0));
    expect(player.speed, equals(1.0));
    expect(player.sequence, equals(null));
    expect(player.hasNext, equals(false));
    expect(player.hasPrevious, equals(false));
    //expect(player.loopMode, equals(LoopMode.off));
    //expect(player.shuffleModeEnabled, equals(false));
    expect(player.automaticallyWaitsToMinimizeStalling, equals(true));
    player.dispose();
  });

  test('load', () async {
    final player = AudioPlayer();
    final duration = await player.setUrl('https://foo.foo/foo.mp3');
    expect(duration, equals(audioSourceDuration));
    expect(player.duration, equals(duration));
    expect(player.processingState, equals(ProcessingState.ready));
    expect(player.position, equals(Duration.zero));
    expect(player.currentIndex, equals(0));
    expect(player.hasNext, equals(false));
    expect(player.hasPrevious, equals(false));
    expect(player.sequence.length, equals(1));
    expect(player.playing, equals(false));
    player.dispose();
  });

  test('load error', () async {
    final player = AudioPlayer();
    var exception;
    try {
      await player.setUrl('https://foo.foo/404.mp3');
      exception = null;
    } catch (e) {
      exception = e;
    }
    expect(exception != null, equals(true));
    try {
      await player.setUrl('https://foo.foo/abort.mp3');
      exception = null;
    } catch (e) {
      exception = e;
    }
    expect(exception != null, equals(true));
    try {
      await player.setUrl('https://foo.foo/error.mp3');
      exception = null;
    } catch (e) {
      exception = e;
    }
    expect(exception != null, equals(true));
    player.dispose();
  });

  test('control', () async {
    final player = AudioPlayer();
    final duration = await player.setUrl('https://foo.foo/foo.mp3');
    final point1 = duration * 0.3;
    final stopwatch = Stopwatch();
    expectState(
      player: player,
      position: Duration.zero,
      processingState: ProcessingState.ready,
      playing: false,
    );
    await player.seek(point1);
    expectState(
      player: player,
      position: point1,
      processingState: ProcessingState.ready,
      playing: false,
    );
    player.play();
    expectState(
      player: player,
      position: point1,
      processingState: ProcessingState.ready,
    );
    await Future.delayed(Duration(milliseconds: 100));
    expectState(player: player, playing: true);
    await Future.delayed(Duration(seconds: 1));
    expectState(
      player: player,
      position: point1 + Duration(seconds: 1),
      processingState: ProcessingState.ready,
      playing: true,
    );
    await player.seek(duration - Duration(seconds: 3));
    expectState(
      player: player,
      position: duration - Duration(seconds: 3),
      processingState: ProcessingState.ready,
      playing: true,
    );
    await player.pause();
    expectState(
      player: player,
      position: duration - Duration(seconds: 3),
      processingState: ProcessingState.ready,
      playing: false,
    );
    stopwatch.reset();
    stopwatch.start();
    final playFuture = player.play();
    expectState(
      player: player,
      position: duration - Duration(seconds: 3),
      processingState: ProcessingState.ready,
    );
    await Future.delayed(Duration(milliseconds: 100));
    expectState(player: player, playing: true);
    await playFuture;
    expectDuration(stopwatch.elapsed, Duration(seconds: 3));
    expectState(
      player: player,
      position: duration,
      processingState: ProcessingState.completed,
      playing: true,
    );
    player.dispose();
  });

  test('speed', () async {
    final player = AudioPlayer();
    final duration = await player.setUrl('https://foo.foo/foo.mp3');
    final period1 = Duration(seconds: 2);
    final period2 = Duration(seconds: 2);
    final speed1 = 0.75;
    final speed2 = 1.5;
    final position1 = period1 * speed1;
    final position2 = position1 + period2 * speed2;
    expectState(player: player, position: Duration.zero);
    await player.setSpeed(speed1);
    player.play();
    await Future.delayed(period1);
    expectState(player: player, position: position1);
    await player.setSpeed(speed2);
    await Future.delayed(period2);
    expectState(player: player, position: position2);
    player.dispose();
  });

  test('positionStream', () async {
    final player = AudioPlayer();
    final duration = await player.setUrl('https://foo.foo/foo.mp3');
    final period = Duration(seconds: 3);
    final position1 = period;
    final position2 = position1 + period;
    final speed1 = 0.75;
    final speed2 = 1.5;
    final stepDuration = period ~/ 5;
    var target = stepDuration;
    player.setSpeed(speed1);
    player.play();
    final stopwatch = Stopwatch();
    stopwatch.start();

    var completer = Completer();
    StreamSubscription subscription;
    subscription = player.positionStream.listen((position) {
      if (position >= position1) {
        subscription.cancel();
        completer.complete();
      } else if (position >= target) {
        expectDuration(position, stopwatch.elapsed * speed1);
        target += stepDuration;
      }
    });
    await completer.future;
    player.setSpeed(speed2);
    stopwatch.reset();

    target = position1 + target;
    completer = Completer();
    subscription = player.positionStream.listen((position) {
      if (position >= position2) {
        subscription.cancel();
        completer.complete();
      } else if (position >= target) {
        expectDuration(position, position1 + stopwatch.elapsed * speed2);
        target += stepDuration;
      }
    });
    await completer.future;
    player.dispose();
  });

  test('icyMetadata', () async {
    final player = AudioPlayer();
    expect(player.icyMetadata, equals(null));
    final duration = await player.setUrl('https://foo.foo/foo.mp3');
    player.play();
    expect(player.icyMetadata.headers.genre, equals(icyMetadata.headers.genre));
    expect((await player.icyMetadataStream.first).headers.genre,
        equals(icyMetadata.headers.genre));
    player.dispose();
  });

  test('proxy', () async {
    final server = MockWebServer();
    await server.start();
    final player = AudioPlayer();
    // This simulates an actual URL
    final uri = Uri.parse(
        'http://${InternetAddress.loopbackIPv4.address}:${server.port}/proxy/foo.mp3');
    await player.setUrl('$uri', headers: {'custom-header': 'Hello'});
    // Obtain the proxy URL that the platform side should use to load the data.
    final proxyUri = Uri.parse(player.icyMetadata.info.url);
    // Simulate the platform side requesting the data.
    final request = await HttpClient().getUrl(proxyUri);
    final response = await request.close();
    final responseText = await response.transform(utf8.decoder).join();
    expect(response.statusCode, equals(HttpStatus.ok));
    expect(responseText, equals('Hello'));
    expect(response.headers.value(HttpHeaders.contentTypeHeader),
        equals('audio/mock'));
    await server.stop();
  });

  test('proxy0.9', () async {
    final server = MockWebServer();
    await server.start();
    final player = AudioPlayer();
    // This simulates an actual URL
    final uri = Uri.parse(
        'http://${InternetAddress.loopbackIPv4.address}:${server.port}/proxy0.9/foo.mp3');
    await player.setUrl('$uri', headers: {'custom-header': 'Hello'});
    // Obtain the proxy URL that the platform side should use to load the data.
    final proxyUri = Uri.parse(player.icyMetadata.info.url);
    // Simulate the platform side requesting the data.
    final socket = await Socket.connect(proxyUri.host, proxyUri.port);
    //final socket = await Socket.connect(uri.host, uri.port);
    socket.write('GET ${uri.path} HTTP/1.1\n' 'test-header: value\n' '\n');
    await socket.flush();
    final responseText = await socket
        .transform(Converter.castFrom<List<int>, String, Uint8List, dynamic>(
            utf8.decoder))
        .join();
    await socket.close();
    expect(responseText, equals('Hello'));
    await server.stop();
  });

  test('sequence', () async {
    final source1 = ConcatenatingAudioSource(children: [
      LoopingAudioSource(
        count: 2,
        child: ClippingAudioSource(
          start: Duration(seconds: 60),
          end: Duration(seconds: 65),
          child: AudioSource.uri(Uri.parse("https://foo.foo/foo.mp3")),
          tag: 'a',
        ),
      ),
      AudioSource.uri(
        Uri.parse("https://bar.bar/bar.mp3"),
        tag: 'b',
      ),
      AudioSource.uri(
        Uri.parse("https://baz.baz/baz.mp3"),
        tag: 'c',
      ),
    ]);
    expect(source1.sequence.map((s) => s.tag as String).toList(),
        equals(['a', 'a', 'b', 'c']));
    final source2 = ConcatenatingAudioSource(children: []);
    final player = AudioPlayer();
    await player.setAudioSource(source2);
    expect(source2.sequence.length, equals(0));
    await source2
        .add(AudioSource.uri(Uri.parse('https://b.b/b.mp3'), tag: 'b'));
    await source2.insert(
        0, AudioSource.uri(Uri.parse('https://a.a/a.mp3'), tag: 'a'));
    await source2.insert(
        2, AudioSource.uri(Uri.parse('https://c.c/c.mp3'), tag: 'c'));
    await source2.addAll([
      AudioSource.uri(Uri.parse('https://d.d/d.mp3'), tag: 'd'),
      AudioSource.uri(Uri.parse('https://e.e/e.mp3'), tag: 'e'),
    ]);
    await source2.insertAll(3, [
      AudioSource.uri(Uri.parse('https://e.e/e.mp3'), tag: 'e'),
      AudioSource.uri(Uri.parse('https://f.f/f.mp3'), tag: 'f'),
    ]);
    expect(source2.sequence.map((s) => s.tag as String),
        equals(['a', 'b', 'c', 'e', 'f', 'd', 'e']));
    await source2.removeAt(0);
    expect(source2.sequence.map((s) => s.tag as String),
        equals(['b', 'c', 'e', 'f', 'd', 'e']));
    await source2.move(3, 2);
    expect(source2.sequence.map((s) => s.tag as String),
        equals(['b', 'c', 'f', 'e', 'd', 'e']));
    await source2.move(2, 3);
    expect(source2.sequence.map((s) => s.tag as String),
        equals(['b', 'c', 'e', 'f', 'd', 'e']));
    await source2.removeRange(0, 2);
    expect(source2.sequence.map((s) => s.tag as String),
        equals(['e', 'f', 'd', 'e']));
    await source2.removeAt(3);
    expect(
        source2.sequence.map((s) => s.tag as String), equals(['e', 'f', 'd']));
    await source2.removeRange(1, 3);
    expect(source2.sequence.map((s) => s.tag as String), equals(['e']));
    await source2.clear();
    expect(source2.sequence.map((s) => s.tag as String), equals([]));
  });

  test('detect', () async {
    expect(AudioSource.uri(Uri.parse('https://a.a/a.mpd')) is DashAudioSource,
        equals(true));
    expect(AudioSource.uri(Uri.parse('https://a.a/a.m3u8')) is HlsAudioSource,
        equals(true));
    expect(
        AudioSource.uri(Uri.parse('https://a.a/a.mp3'))
            is ProgressiveAudioSource,
        equals(true));
    expect(AudioSource.uri(Uri.parse('https://a.a/a#.mpd')) is DashAudioSource,
        equals(true));
  });

  test('shuffle order', () async {
    final shuffleOrder1 = DefaultShuffleOrder(random: Random(1001));
    checkIndices(shuffleOrder1.indices, 0);
    //expect(shuffleOrder1.indices, equals([]));
    shuffleOrder1.insert(0, 5);
    //expect(shuffleOrder1.indices, equals([3, 0, 2, 4, 1]));
    checkIndices(shuffleOrder1.indices, 5);
    shuffleOrder1.insert(3, 2);
    checkIndices(shuffleOrder1.indices, 7);
    shuffleOrder1.insert(0, 2);
    checkIndices(shuffleOrder1.indices, 9);
    shuffleOrder1.insert(9, 2);
    checkIndices(shuffleOrder1.indices, 11);

    final indices1 = List.of(shuffleOrder1.indices);
    shuffleOrder1.shuffle();
    expect(shuffleOrder1.indices, isNot(indices1));
    checkIndices(shuffleOrder1.indices, 11);
    final indices2 = List.of(shuffleOrder1.indices);
    shuffleOrder1.shuffle(initialIndex: 5);
    expect(shuffleOrder1.indices[0], equals(5));
    expect(shuffleOrder1.indices, isNot(indices2));
    checkIndices(shuffleOrder1.indices, 11);

    shuffleOrder1.removeRange(4, 6);
    checkIndices(shuffleOrder1.indices, 9);
    shuffleOrder1.removeRange(0, 2);
    checkIndices(shuffleOrder1.indices, 7);
    shuffleOrder1.removeRange(5, 7);
    checkIndices(shuffleOrder1.indices, 5);
    shuffleOrder1.removeRange(0, 5);
    checkIndices(shuffleOrder1.indices, 0);

    shuffleOrder1.insert(0, 5);
    checkIndices(shuffleOrder1.indices, 5);
    shuffleOrder1.clear();
    checkIndices(shuffleOrder1.indices, 0);
  });

  test('shuffle', () async {
    AudioSource createSource() => ConcatenatingAudioSource(
          shuffleOrder: DefaultShuffleOrder(random: Random(1001)),
          children: [
            LoopingAudioSource(
              count: 2,
              child: ClippingAudioSource(
                start: Duration(seconds: 60),
                end: Duration(seconds: 65),
                child: AudioSource.uri(Uri.parse("https://foo.foo/foo.mp3")),
                tag: 'a',
              ),
            ),
            AudioSource.uri(
              Uri.parse("https://bar.bar/bar.mp3"),
              tag: 'b',
            ),
            AudioSource.uri(
              Uri.parse("https://baz.baz/baz.mp3"),
              tag: 'c',
            ),
            ClippingAudioSource(
              child: AudioSource.uri(
                Uri.parse("https://baz.baz/baz.mp3"),
                tag: 'd',
              ),
            ),
          ],
        );
    final source1 = createSource();
    //expect(source1.shuffleIndices, [4, 0, 1, 3, 2]);
    checkIndices(source1.shuffleIndices, 5);
    expect(source1.shuffleIndices.skipWhile((i) => i != 0).skip(1).first,
        equals(1));
    final player1 = AudioPlayer();
    await player1.setAudioSource(source1);
    checkIndices(player1.shuffleIndices, 5);
    expect(player1.shuffleIndices.first, equals(0));
    await player1.seek(Duration.zero, index: 3);
    await player1.shuffle();
    checkIndices(player1.shuffleIndices, 5);
    expect(player1.shuffleIndices.first, equals(3));

    final source2 = createSource();
    final player2 = AudioPlayer();
    await player2.setAudioSource(source2, initialIndex: 3);
    checkIndices(player2.shuffleIndices, 5);
    expect(player2.shuffleIndices.first, equals(3));
  });

  test('stop', () async {
    final source = ConcatenatingAudioSource(
      shuffleOrder: DefaultShuffleOrder(random: Random(1001)),
      children: [
        AudioSource.uri(
          Uri.parse("https://bar.bar/foo.mp3"),
          tag: 'foo',
        ),
        AudioSource.uri(
          Uri.parse("https://baz.baz/bar.mp3"),
          tag: 'bar',
        ),
      ],
    );
    final player = AudioPlayer();
    expect(player.processingState, ProcessingState.idle);
    await player.setAudioSource(source, preload: false);
    expect(player.processingState, ProcessingState.idle);
    await player.load();
    expect(player.processingState, ProcessingState.ready);
    await player.seek(Duration(seconds: 5), index: 1);
    await player.setVolume(0.5);
    await player.setSpeed(0.7);
    await player.setShuffleModeEnabled(true);
    await player.setLoopMode(LoopMode.one);
    await player.stop();
    expect(player.processingState, ProcessingState.idle);
    expect(player.position, Duration(seconds: 5));
    expect(player.volume, 0.5);
    expect(player.speed, 0.7);
    expect(player.shuffleModeEnabled, true);
    expect(player.loopMode, LoopMode.one);
    await player.load();
    expect(player.processingState, ProcessingState.ready);
    expect(player.position, Duration(seconds: 5));
    expect(player.volume, 0.5);
    expect(player.speed, 0.7);
    expect(player.shuffleModeEnabled, true);
    expect(player.loopMode, LoopMode.one);
  });
}

class MockJustAudio extends Mock
    with MockPlatformInterfaceMixin
    implements JustAudioPlatform {
  final _players = <String, MockAudioPlayer>{};

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final player = MockAudioPlayer(request.id);
    _players[request.id] = player;
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
      DisposePlayerRequest request) async {
    _players[request.id].dispose(DisposeRequest());
    return DisposePlayerResponse();
  }
}

const audioSourceDuration = Duration(minutes: 2);

final icyMetadata = IcyMetadata(
  headers: IcyHeaders(
    url: 'url',
    genre: 'Genre',
    metadataInterval: 3,
    bitrate: 100,
    isPublic: true,
    name: 'name',
  ),
  info: IcyInfo(
    title: 'title',
    url: 'url',
  ),
);

final icyMetadataMessage = IcyMetadataMessage(
  headers: IcyHeadersMessage(
    url: 'url',
    genre: 'Genre',
    metadataInterval: 3,
    bitrate: 100,
    isPublic: true,
    name: 'name',
  ),
  info: IcyInfoMessage(
    title: 'title',
    url: 'url',
  ),
);

class MockAudioPlayer implements AudioPlayerPlatform {
  final String _id;
  final eventController = StreamController<PlaybackEventMessage>();
  AudioSourceMessage _audioSource;
  ProcessingStateMessage _processingState;
  Duration _updatePosition;
  DateTime _updateTime;
  Duration _duration = audioSourceDuration;
  int _currentIndex;
  int _index;
  var _playing = false;
  var _speed = 1.0;
  var _volume = 1.0;
  var _loopMode = LoopModeMessage.off;
  var _shuffleModeEnabled = false;
  Completer<dynamic> _playCompleter;
  Timer _playTimer;

  MockAudioPlayer(String id) : this._id = id;

  @override
  String get id => _id;

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      eventController.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    final audioSource = request.audioSourceMessage;
    if (audioSource is UriAudioSourceMessage) {
      if (audioSource.uri.contains('abort')) {
        throw PlatformException(code: 'abort', message: 'Failed to load URL');
      } else if (audioSource.uri.contains('404')) {
        throw PlatformException(code: '404', message: 'Not found');
      } else if (audioSource.uri.contains('error')) {
        throw PlatformException(code: 'error', message: 'Unknown error');
      }
    }
    _audioSource = audioSource;
    _index = request.initialIndex ?? 0;
    _setPosition(request.initialPosition ?? Duration.zero);
    _processingState = ProcessingStateMessage.ready;
    _broadcastPlaybackEvent();
    return LoadResponse(duration: _duration);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    if (_playing) return PlayResponse();
    _playing = true;
    _playTimer = Timer(_remaining, () {
      _setPosition(_position);
      _processingState = ProcessingStateMessage.completed;
      _broadcastPlaybackEvent();
      _playCompleter?.complete();
    });
    _playCompleter = Completer();
    _broadcastPlaybackEvent();
    await _playCompleter.future;
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    if (!_playing) return PauseResponse();
    _playing = false;
    _playTimer?.cancel();
    _playCompleter?.complete();
    _setPosition(_position);
    _broadcastPlaybackEvent();
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    _setPosition(request.position);
    _index = request.index;
    _broadcastPlaybackEvent();
    return SeekResponse();
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
    return SetShuffleOrderResponse();
  }

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async {
    _speed = request.speed;
    _setPosition(_position);
    return SetSpeedResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async {
    _volume = request.volume;
    return SetVolumeResponse();
  }

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    _processingState = ProcessingStateMessage.idle;
    _broadcastPlaybackEvent();
    return DisposeResponse();
  }

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
      ConcatenatingInsertAllRequest request) async {
    // TODO
    return ConcatenatingInsertAllResponse();
  }

  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(
      ConcatenatingMoveRequest request) async {
    // TODO
    return ConcatenatingMoveResponse();
  }

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
      ConcatenatingRemoveRangeRequest request) async {
    // TODO
    return ConcatenatingRemoveRangeResponse();
  }

  _broadcastPlaybackEvent() {
    String url;
    if (_audioSource is UriAudioSourceMessage) {
      // Not sure why this cast is necessary...
      url = (_audioSource as UriAudioSourceMessage).uri.toString();
    }
    eventController.add(PlaybackEventMessage(
      processingState: _processingState,
      updatePosition: _updatePosition,
      updateTime: _updateTime,
      bufferedPosition: _position ?? Duration.zero,
      icyMetadata: IcyMetadataMessage(
        headers: IcyHeadersMessage(
          url: url,
          genre: 'Genre',
          metadataInterval: 3,
          bitrate: 100,
          isPublic: true,
          name: 'name',
        ),
        info: IcyInfoMessage(
          title: 'title',
          url: url,
        ),
      ),
      duration: _duration,
      currentIndex: _index,
      androidAudioSessionId: null,
    ));
  }

  Duration get _position {
    if (_playing && _processingState == ProcessingStateMessage.ready) {
      final result =
          _updatePosition + (DateTime.now().difference(_updateTime)) * _speed;
      return _duration == null || result <= _duration ? result : _duration;
    } else {
      return _updatePosition;
    }
  }

  Duration get _remaining => (_duration - _position) * (1 / _speed);

  void _setPosition(Duration position) {
    _updatePosition = position;
    _updateTime = DateTime.now();
  }
}

class MockWebServer {
  HttpServer _server;
  int get port => _server.port;

  Future start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      final response = request.response;
      final body = utf8.encode('${request.headers.value("custom-header")}');
      if (request.uri.path == '/proxy0.9/foo.mp3') {
        final clientSocket =
            await request.response.detachSocket(writeHeaders: false);
        clientSocket.add(body);
        await clientSocket.flush();
        await clientSocket.close();
      } else {
        response.contentLength = body.length;
        response.statusCode = HttpStatus.ok;
        response.headers.set(HttpHeaders.contentTypeHeader, 'audio/mock');
        response.add(body);
        await response.flush();
        await response.close();
      }
    });
  }

  Future stop() => _server.close();
}

class MyHttpOverrides extends HttpOverrides {}
