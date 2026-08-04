import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:rxdart/rxdart.dart';
import 'package:synchronized/synchronized.dart';

export 'package:audio_service/audio_service.dart' show MediaItem;

/// Logging levels for just_audio_background diagnostic logging
/// Uses the same LogLevel enum as just_audio for consistency
enum LogLevel {
  /// Enable all logging categories (queueOperations, handlerState, concurrentOps, platformCalls, errorContext, performanceMetrics)
  /// Use for comprehensive debugging and development
  VERBOSE,

  /// Enable most logging categories (queueOperations, concurrentOps, platformCalls, errorContext)
  /// Excludes performanceMetrics and handlerState to reduce noise
  /// Use for general debugging
  DEBUG,

  /// Enable only essential operational logging (queueOperations, errorContext)
  /// Use for monitoring key operations without overwhelming detail
  INFO,

  /// Enable only error-related logging (errorContext)
  /// Use for production error tracking
  ERROR,

  /// Disable all logging (default for production)
  /// Use for production to ensure zero performance impact
  OFF,
}

/// Background Audio Player Diagnostic Logging Configuration
///
/// Provides comprehensive logging for debugging background audio operations,
/// concurrent access issues, and platform integration problems.
///
/// Usage:
/// ```dart
/// // Enable comprehensive debugging
/// BackgroundAudioLogging.setLevel(LogLevel.VERBOSE);
///
/// // Enable general debugging (recommended)
/// BackgroundAudioLogging.setLevel(LogLevel.DEBUG);
///
/// // Enable only essential operations
/// BackgroundAudioLogging.setLevel(LogLevel.INFO);
///
/// // Enable only error tracking
/// BackgroundAudioLogging.setLevel(LogLevel.ERROR);
///
/// // Disable all logging (default)
/// BackgroundAudioLogging.setLevel(LogLevel.OFF);
/// ```
class BackgroundAudioLogging {
  /// Current logging level
  static LogLevel _level = LogLevel.OFF;

  /// Internal granular logging controls (set automatically by logging level)
  static bool _queueOperations = false;    // Queue insert/remove operations
  static bool _handlerState = false;       // Audio handler state transitions
  static bool _concurrentOps = false;      // Concurrent operation detection
  static bool _platformCalls = false;      // Platform method calls
  static bool _errorContext = false;       // Enhanced error context
  static bool _performanceMetrics = false; // Operation timing and performance

  /// Set the logging level (primary public API)
  static void setLevel(LogLevel level) {
    _level = level;
    _updateLoggingFlags();
  }

  /// Get the current logging level
  static LogLevel get level => _level;

  /// Check if logging is enabled (any level except OFF)
  static bool get enabled => _level != LogLevel.OFF;

  /// Internal method to update logging flags based on current level
  static void _updateLoggingFlags() {
    switch (_level) {
      case LogLevel.VERBOSE:
        _queueOperations = true;
        _handlerState = true;
        _concurrentOps = true;
        _platformCalls = true;
        _errorContext = true;
        _performanceMetrics = true;
        break;
      case LogLevel.DEBUG:
        _queueOperations = true;
        _handlerState = false;  // Excluded to reduce noise
        _concurrentOps = true;
        _platformCalls = true;
        _errorContext = true;
        _performanceMetrics = false;  // Excluded to reduce noise
        break;
      case LogLevel.INFO:
        _queueOperations = true;
        _handlerState = false;
        _concurrentOps = false;
        _platformCalls = false;
        _errorContext = true;
        _performanceMetrics = false;
        break;
      case LogLevel.ERROR:
        _queueOperations = false;
        _handlerState = false;
        _concurrentOps = false;
        _platformCalls = false;
        _errorContext = true;
        _performanceMetrics = false;
        break;
      case LogLevel.OFF:
        _queueOperations = false;
        _handlerState = false;
        _concurrentOps = false;
        _platformCalls = false;
        _errorContext = false;
        _performanceMetrics = false;
        break;
    }
  }

  /// Backward compatibility getters (internal use)
  static bool get queueOperations => _queueOperations;
  static bool get handlerState => _handlerState;
  static bool get concurrentOps => _concurrentOps;
  static bool get platformCalls => _platformCalls;
  static bool get errorContext => _errorContext;
  static bool get performanceMetrics => _performanceMetrics;

  /// Backward compatibility methods (deprecated - use setLevel instead)
  @Deprecated('Use setLevel(LogLevel.VERBOSE) instead')
  static void enableAll() => setLevel(LogLevel.VERBOSE);

  @Deprecated('Use setLevel(LogLevel.OFF) instead')
  static void disableAll() => setLevel(LogLevel.OFF);

  @Deprecated('Use setLevel(LogLevel.ERROR) instead')
  static void enableErrorsOnly() => setLevel(LogLevel.ERROR);

  /// Conditional debug print that respects logging configuration
  static void log(String message, {String category = 'general'}) {
    if (!enabled) return;

    bool shouldLog = switch (category) {
      'queue' => _queueOperations,
      'handler' => _handlerState,
      'concurrent' => _concurrentOps,
      'platform' => _platformCalls,
      'error' => _errorContext,
      'performance' => _performanceMetrics,
      _ => true,
    };

    if (shouldLog) {
      debugPrint('[JustAudioBackground][$category] $message');
    }
  }
}

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
  String? _playerId;

  _JustAudioBackgroundPlugin();

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    if (_playerId != null) {
      throw PlatformException(
        code: "error",
        message: "just_audio_background supports only a single player instance",
      );
    }
    _playerId = request.id;
    _player ??= _JustAudioPlayer(initRequest: request);
    return _player!;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
      DisposePlayerRequest request) async {
    if (request.id == _playerId) {
      _playerId = null;
      final player = _player;
      _player = null;
      await player?.release();
    }
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
      DisposeAllPlayersRequest request) async {
    final player = _player;
    _player = null;
    await player?.release();
    return DisposeAllPlayersResponse();
  }
}

final _PlayerAudioHandler _playerAudioHandler = _PlayerAudioHandler();

class _JustAudioPlayer extends AudioPlayerPlatform {
  final InitRequest initRequest;
  final eventController =
      StreamController<PlaybackEventMessage>.broadcast(sync: true);
  final playerDataController =
      StreamController<PlayerDataMessage>.broadcast(sync: true);

  _JustAudioPlayer({required this.initRequest}) : super(initRequest.id) {
    eventController.onCancel = _playerAudioHandler.cancelStreamSubscriptions;
    _playerAudioHandler._initPlayer(initRequest);
    _audioHandler.inner = _playerAudioHandler;
    _audioHandler.customEvent
        .whereType<PlaybackEventMessage>()
        .listen(eventController.add);
    _audioHandler.customEvent
        .whereType<_PlayingEvent>()
        .map((event) => event.playing)
        .distinct()
        .listen((playing) {
      playerDataController.add(PlayerDataMessage(playing: playing));
    });
  }

  PlaybackState get playbackState => _audioHandler.playbackState.nvalue!;

  Future<void> release() async {
    await _audioHandler.stop();
  }

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      eventController.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream =>
      playerDataController.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) =>
      _playerAudioHandler.customLoad(request);

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
    await _playerAudioHandler.setSpeed(request.speed);
    return SetSpeedResponse();
  }

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async {
    await _playerAudioHandler.customSetPitch(request);
    return SetPitchResponse();
  }

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(
      SetSkipSilenceRequest request) async {
    await _playerAudioHandler.customSetSkipSilence(request);
    return SetSkipSilenceResponse();
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
  Future<SetWebCrossOriginResponse> setWebCrossOrigin(
      SetWebCrossOriginRequest request) async {
    _playerAudioHandler.customSetWebCrossOrigin(request);
    return SetWebCrossOriginResponse();
  }

  @override
  Future<SetWebSinkIdResponse> setWebSinkId(SetWebSinkIdRequest request) {
    _playerAudioHandler.customSetWebSinkId(request);
    throw SetWebSinkIdResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) =>
      _playerAudioHandler.customPlayerSeek(request);

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
          ConcatenatingInsertAllRequest request) =>
      _playerAudioHandler.customConcatenatingInsertAll(request);

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
          ConcatenatingRemoveRangeRequest request) =>
      _playerAudioHandler.customConcatenatingRemoveRange(request);

  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(
          ConcatenatingMoveRequest request) =>
      _playerAudioHandler.customConcatenatingMove(request);

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
          SetAndroidAudioAttributesRequest request) =>
      _playerAudioHandler.customSetAndroidAudioAttributes(request);

  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
      setAutomaticallyWaitsToMinimizeStalling(
              SetAutomaticallyWaitsToMinimizeStallingRequest request) =>
          _playerAudioHandler
              .customSetAutomaticallyWaitsToMinimizeStalling(request);

  @override
  Future<AndroidEqualizerBandSetGainResponse> androidEqualizerBandSetGain(
          AndroidEqualizerBandSetGainRequest request) =>
      _playerAudioHandler.customAndroidEqualizerBandSetGain(request);

  @override
  Future<AndroidEqualizerGetParametersResponse> androidEqualizerGetParameters(
          AndroidEqualizerGetParametersRequest request) =>
      _playerAudioHandler.customAndroidEqualizerGetParameters(request);

  @override
  Future<AndroidLoudnessEnhancerSetTargetGainResponse>
      androidLoudnessEnhancerSetTargetGain(
              AndroidLoudnessEnhancerSetTargetGainRequest request) =>
          _playerAudioHandler
              .customAndroidLoudnessEnhancerSetTargetGain(request);

  @override
  Future<AudioEffectSetEnabledResponse> audioEffectSetEnabled(
          AudioEffectSetEnabledRequest request) =>
      _playerAudioHandler.customAudioEffectSetEnabled(request);

  @override
  Future<SetAllowsExternalPlaybackResponse> setAllowsExternalPlayback(
          SetAllowsExternalPlaybackRequest request) =>
      _playerAudioHandler.customSetAllowsExternalPlayback(request);

  @override
  Future<SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse>
      setCanUseNetworkResourcesForLiveStreamingWhilePaused(
              SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest
                  request) =>
          _playerAudioHandler
              .customSetCanUseNetworkResourcesForLiveStreamingWhilePaused(
                  request);

  @override
  Future<SetPreferredPeakBitRateResponse> setPreferredPeakBitRate(
          SetPreferredPeakBitRateRequest request) =>
      _playerAudioHandler.customSetPreferredPeakBitRate(request);
}

class _PlayerAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final _lock = Lock();
  var _playerCompleter = _ValueCompleter<AudioPlayerPlatform>();
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
  List<int> _shuffleIndices = [];
  List<int> _shuffleIndicesInv = [];
  List<int> _effectiveIndices = [];
  List<int> _effectiveIndicesInv = [];

  // Concurrent operation tracking for enhanced error handling
  final _activeOperations = <String, DateTime>{};
  int _operationDepth = 0;

  /// Retry background platform operations with exponential backoff for transient failures
  Future<T> _retryBackgroundPlatformOperation<T>({
    required Future<T> Function() operation,
    required String operationName,
    required Map<String, dynamic> context,
    required DateTime startTime,
    int maxRetries = 3,
    Duration initialDelay = const Duration(milliseconds: 100),
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (attempt <= maxRetries) {
      try {
        return await operation();
      } on PlatformException catch (e) {
        attempt++;
        final duration = DateTime.now().difference(startTime);

        // Check if this is a retryable error
        final isRetryable = _isRetryableBackgroundPlatformException(e);

        if (!isRetryable || attempt > maxRetries) {
          debugPrint('JustAudioBackground: $operationName platform error (final) - '
              'attempt=$attempt, duration=${duration.inMilliseconds}ms, '
              'code=${e.code}, message=${e.message}, details=${e.details}, '
              'stackTrace=${e.stacktrace}, context=$context, '
              'isRetryable=$isRetryable, maxRetries=$maxRetries');

          // Enhanced error context for platform exceptions
          throw PlatformException(
            code: e.code,
            message: 'JustAudioBackground.$operationName platform operation failed: '
                'context=$context, attempt=$attempt, '
                'duration=${duration.inMilliseconds}ms, '
                'isRetryable=$isRetryable, maxRetries=$maxRetries, '
                'originalError=${e.message}, originalDetails=${e.details}',
            details: e.details,
          );
        }

        debugPrint('JustAudioBackground: $operationName platform error (retrying) - '
            'attempt=$attempt, duration=${duration.inMilliseconds}ms, '
            'code=${e.code}, message=${e.message}, details=${e.details}, '
            'stackTrace=${e.stacktrace}, retryDelay=${delay.inMilliseconds}ms, '
            'isRetryable=$isRetryable, context=$context');

        // Wait before retry with exponential backoff
        await Future<void>.delayed(delay);
        delay = Duration(milliseconds: (delay.inMilliseconds * 1.5).round());
      } catch (e) {
        // Non-platform exceptions are not retryable
        final duration = DateTime.now().difference(startTime);
        debugPrint('JustAudioBackground: $operationName non-platform error - '
            'attempt=$attempt, duration=${duration.inMilliseconds}ms, '
            'error=$e, context=$context');
        rethrow;
      }
    }

    // This should never be reached, but just in case
    throw Exception('JustAudioBackground.$operationName: Maximum retries exceeded');
  }

  /// Check if a PlatformException is retryable in background operations
  bool _isRetryableBackgroundPlatformException(PlatformException e) {
    // Retry on specific error codes that indicate transient issues
    const retryableCodes = [
      'Error', // Generic platform errors that might be transient
      'IllegalArgumentException', // Often caused by race conditions
      'IllegalStateException', // May be caused by timing issues
      'ConcurrentModificationException', // Concurrent access issues
    ];

    // Check for concurrent operation indicators in the message
    final message = e.message?.toLowerCase() ?? '';
    const concurrentIndicators = [
      'concurrent',
      'reentrant',
      'illegal',
      'state',
      'argument',
      'modification',
      'thread',
      'synchronization',
    ];

    return retryableCodes.contains(e.code) ||
           concurrentIndicators.any((indicator) => message.contains(indicator));
  }

  Future<AudioPlayerPlatform> get _player => _playerCompleter.future;
  int? index;
  MediaItem? get currentMediaItem =>
      index != null && index! >= 0 && index! < currentQueue.length
          ? currentQueue[index!]
          : null;

  List<MediaItem> get currentQueue => queue.value;
  StreamSubscription<TrackInfo>? _trackInfoSubscription;

  Future<void> _initPlayer(InitRequest initRequest) =>
      _lock.synchronized(() async {
        final player = await _platform.init(initRequest);
        _playerCompleter.complete(player);
        final playbackEventMessageStream = player.playbackEventMessageStream;
        _trackInfoSubscription = playbackEventMessageStream
            .map((event) {
              index = event.currentIndex ?? _justAudioEvent.currentIndex;
              _justAudioEvent = event;
              customEvent.add(event);
              _broadcastState();
              return event;
            })
            .map((event) => TrackInfo(event.currentIndex, event.duration))
            .distinct()
            .debounceTime(const Duration(milliseconds: 100))
            .map((track) {
              // Platform may send us a null duration on dispose, which we should
              // ignore.
              final currentMediaItem = this.currentMediaItem;
              if (currentMediaItem != null) {
                if (track.duration == null &&
                    currentMediaItem.duration != null) {
                  return TrackInfo(track.index, currentMediaItem.duration);
                }
              }
              return track;
            })
            .distinct()
            .listen((track) {
              if (currentMediaItem != null && index != null) {
                if (track.duration != currentMediaItem!.duration &&
                    (index! < queue.nvalue!.length && track.duration != null)) {
                  currentQueue[index!] =
                      currentQueue[index!].copyWith(duration: track.duration);
                  queue.add(currentQueue);
                }
                mediaItem.add(currentMediaItem!);
              }
            }, onError: (Object e, [StackTrace? st]) {});
      });

  Future<void> cancelStreamSubscriptions() async {
    final trackInfoSubscription = _trackInfoSubscription;
    if (trackInfoSubscription != null) {
      _trackInfoSubscription = null;
      await trackInfoSubscription.cancel();
    }
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
    _updateShuffleIndices();
    _updateQueue();
    final response = await (await _player).load(LoadRequest(
      audioSourceMessage: _source!,
      initialPosition: request.initialPosition,
      initialIndex: request.initialIndex,
    ));
    return LoadResponse(duration: response.duration);
  }

  Future<SetVolumeResponse> customSetVolume(SetVolumeRequest request) async =>
      await (await _player).setVolume(request);

  Future<SetSpeedResponse> customSetSpeed(SetSpeedRequest request) async =>
      await (await _player).setSpeed(request);

  Future<SetPitchResponse> customSetPitch(SetPitchRequest request) async =>
      await (await _player).setPitch(request);

  Future<SetSkipSilenceResponse> customSetSkipSilence(
          SetSkipSilenceRequest request) async =>
      await (await _player).setSkipSilence(request);

  Future<SeekResponse> customPlayerSeek(SeekRequest request) async =>
      await (await _player).seek(request);

  Future<SetShuffleOrderResponse> customSetShuffleOrder(
      SetShuffleOrderRequest request) async {
    _source = request.audioSourceMessage;
    _updateShuffleIndices();
    _broadcastStateIfActive();
    return await (await _player).setShuffleOrder(SetShuffleOrderRequest(
      audioSourceMessage: _source!,
    ));
  }

  Future<SetWebCrossOriginResponse> customSetWebCrossOrigin(
      SetWebCrossOriginRequest request) async {
    return await (await _player).setWebCrossOrigin(request);
  }

  Future<SetWebSinkIdResponse> customSetWebSinkId(
      SetWebSinkIdRequest request) async {
    return await (await _player).setWebSinkId(request);
  }

  Future<ConcatenatingInsertAllResponse> customConcatenatingInsertAll(
      ConcatenatingInsertAllRequest request) async {
    final operationId = 'insertAll_${request.id}_${DateTime.now().millisecondsSinceEpoch}';
    final startTime = DateTime.now();

    // Enhanced diagnostic logging - operation start with complete state
    BackgroundAudioLogging.log(
      'customConcatenatingInsertAll starting - '
      'operationId=$operationId, id=${request.id}, index=${request.index}, '
      'childrenToInsert=${request.children.length}, '
      'requestShuffleOrderLength=${request.shuffleOrder.length}, '
      'operationDepth=$_operationDepth, activeOperations=${_activeOperations.length}, '
      'timestamp=${DateTime.now().toIso8601String()}',
      category: 'queue',
    );

    debugPrint('JustAudioBackground: customConcatenatingInsertAll starting - '
        'operationId=$operationId, id=${request.id}, index=${request.index}, '
        'childrenToInsert=${request.children.length}, '
        'requestShuffleOrderLength=${request.shuffleOrder.length}, '
        'operationDepth=$_operationDepth, activeOperations=${_activeOperations.length}, '
        'timestamp=${DateTime.now().toIso8601String()}');

    // Track concurrent operations
    _operationDepth++;
    _activeOperations[operationId] = startTime;

    try {
      final cat = _source!.findCat(request.id);
      if (cat == null) {
        debugPrint('JustAudioBackground: ConcatenatingAudioSource not found - '
            'id=${request.id}, operationDepth=$_operationDepth');
        throw Exception(
          'ConcatenatingAudioSource not found: id=${request.id}, '
          'operation=insertAll, index=${request.index}, '
          'operationDepth=$_operationDepth, activeOperations=${_activeOperations.length}'
        );
      }

      // Validate index bounds before attempting insertion
      if (request.index < 0 || request.index > cat.children.length) {
        debugPrint('JustAudioBackground: insertAll validation failed - '
            'id=${request.id}, index=${request.index}, '
            'currentLength=${cat.children.length}');
        throw RangeError.index(
          request.index,
          cat.children,
          'index',
          'Index out of range for ConcatenatingAudioSource insertAll: '
          'id=${request.id}, childrenLength=${cat.children.length}, '
          'operationDepth=$_operationDepth',
          cat.children.length,
        );
      }

      // Detect potential concurrent operation conflicts
      if (_operationDepth > 1) {
        final activeOps = _activeOperations.keys.where((key) => key != operationId).toList();
        // Log concurrent operation warning for debugging
        debugPrint('JustAudioBackground: Concurrent operation detected - '
            'operation=$operationId, depth=$_operationDepth, '
            'activeOperations=$activeOps');
      }

      // Store context for error reporting and detailed state logging
      final childrenLength = cat.children.length;
      final shuffleOrderLength = cat.shuffleOrder.length;

      // SCENARIO B: Critical pre-insertAll validation logging
      BackgroundAudioLogging.log(
        'SCENARIO_B_ANALYSIS: insertAll pre-operation validation - '
        'operationId=$operationId, '
        'requestedIndex=${request.index}, currentQueueLength=$childrenLength, '
        'isIndexValid=${request.index >= 0 && request.index <= childrenLength}, '
        'childrenToInsert=${request.children.length}, '
        'requestShuffleOrderLength=${request.shuffleOrder.length}, '
        'currentShuffleOrderLength=$shuffleOrderLength, '
        'shuffleOrderConsistency=${shuffleOrderLength == childrenLength}, '
        'operationDepth=$_operationDepth, '
        'concurrentOperations=${_activeOperations.length}, '
        'handlerState=${_source != null ? "active" : "inactive"}, '
        'mutexStatus=acquired',
        category: 'error',
      );

      debugPrint('JustAudioBackground: insertAll pre-modification state - '
          'operationId=$operationId, id=${request.id}, index=${request.index}, '
          'currentChildrenLength=$childrenLength, currentShuffleOrderLength=$shuffleOrderLength, '
          'currentChildrenTypes=[${cat.children.map((c) => c.runtimeType.toString()).join(', ')}], '
          'insertChildrenTypes=[${request.children.map((c) => c.runtimeType.toString()).join(', ')}], '
          'requestShuffleOrder=[${request.shuffleOrder.join(', ')}], '
          'currentShuffleOrder=[${cat.shuffleOrder.join(', ')}]');

      try {
        cat.children.insertAll(request.index, request.children);
        cat.shuffleOrder
            .replaceRange(0, cat.shuffleOrder.length, request.shuffleOrder);

        // Log state after local modification
        debugPrint('JustAudioBackground: insertAll post-modification state - '
            'operationId=$operationId, id=${request.id}, '
            'newChildrenLength=${cat.children.length}, newShuffleOrderLength=${cat.shuffleOrder.length}, '
            'newChildrenTypes=[${cat.children.map((c) => c.runtimeType.toString()).join(', ')}], '
            'newShuffleOrder=[${cat.shuffleOrder.join(', ')}], '
            'insertedAt=${request.index}, insertedCount=${request.children.length}');

        _updateShuffleIndices();
        _broadcastStateIfActive();
        _updateQueue();

        // SCENARIO B: Critical platform call logging
        BackgroundAudioLogging.log(
          'SCENARIO_B_ANALYSIS: insertAll calling platform - '
          'operationId=$operationId, '
          'platformRequest={id: ${request.id}, index: ${request.index}, '
          'childrenCount: ${request.children.length}, shuffleOrderLength: ${request.shuffleOrder.length}}, '
          'preCallQueueLength=${cat.children.length}, '
          'preCallShuffleOrder=[${cat.shuffleOrder.join(', ')}], '
          'operationDepth=$_operationDepth, '
          'concurrentOperations=${_activeOperations.keys.toList()}',
          category: 'platform',
        );

        debugPrint('JustAudioBackground: insertAll calling platform - '
            'operationId=$operationId, id=${request.id}, newLength=${cat.children.length}, '
            'platformRequestDetails={id: ${request.id}, index: ${request.index}, '
            'childrenCount: ${request.children.length}, shuffleOrderLength: ${request.shuffleOrder.length}}');

        // Enhanced platform operation with retry logic for IllegalArgumentException
        final result = await _retryBackgroundPlatformOperation(
          operation: () async {
            return await (await _player).concatenatingInsertAll(request);
          },
          operationName: 'insertAll',
          context: {
            'operationId': operationId,
            'id': request.id,
            'index': request.index,
            'childrenLength': childrenLength,
            'shuffleOrderLength': shuffleOrderLength,
            'childrenToInsert': request.children.length,
            'operationDepth': _operationDepth,
          },
          startTime: startTime,
        );

        final duration = DateTime.now().difference(startTime);

        // SCENARIO B: Success logging with state verification
        BackgroundAudioLogging.log(
          'SCENARIO_B_ANALYSIS: insertAll completed successfully - '
          'operationId=$operationId, '
          'postCallQueueLength=${cat.children.length}, '
          'postCallShuffleOrder=[${cat.shuffleOrder.join(', ')}], '
          'duration=${duration.inMilliseconds}ms, '
          'stateConsistency=${cat.shuffleOrder.length == cat.children.length}, '
          'operationDepth=$_operationDepth',
          category: 'queue',
        );

        debugPrint('JustAudioBackground: insertAll completed successfully - '
            'id=${request.id}, duration=${duration.inMilliseconds}ms');

        return result;
      } catch (e) {
        final duration = DateTime.now().difference(startTime);
        debugPrint('JustAudioBackground: insertAll failed - '
            'id=${request.id}, duration=${duration.inMilliseconds}ms, error=$e');

        // Enhanced error context for debugging
        throw Exception(
          'ConcatenatingAudioSource.insertAll failed: '
          'id=${request.id}, index=${request.index}, '
          'childrenLength=$childrenLength, '
          'shuffleOrderLength=$shuffleOrderLength, '
          'childrenToInsert=${request.children.length}, '
          'operationDepth=$_operationDepth, '
          'duration=${duration.inMilliseconds}ms, error=$e'
        );
      }
    } finally {
      // Clean up operation tracking
      _activeOperations.remove(operationId);
      _operationDepth--;

      final totalDuration = DateTime.now().difference(startTime);
      debugPrint('JustAudioBackground: insertAll operation cleanup - '
          'id=${request.id}, totalDuration=${totalDuration.inMilliseconds}ms, '
          'remainingDepth=$_operationDepth');
    }
  }

  Future<ConcatenatingRemoveRangeResponse> customConcatenatingRemoveRange(
      ConcatenatingRemoveRangeRequest request) async {
    final operationId = 'removeRange_${request.id}_${DateTime.now().millisecondsSinceEpoch}';
    final startTime = DateTime.now();

    // Track concurrent operations
    _operationDepth++;
    _activeOperations[operationId] = startTime;

    try {
      final cat = _source!.findCat(request.id);
      if (cat == null) {
        throw Exception(
          'ConcatenatingAudioSource not found: id=${request.id}, '
          'operation=removeRange, startIndex=${request.startIndex}, '
          'endIndex=${request.endIndex}, operationDepth=$_operationDepth, '
          'activeOperations=${_activeOperations.length}'
        );
      }

      // Validate index bounds before attempting removal
      if (request.startIndex < 0 ||
          request.endIndex > cat.children.length ||
          request.startIndex >= request.endIndex) {
        throw RangeError(
          'Invalid range for ConcatenatingAudioSource removeRange: '
          'id=${request.id}, startIndex=${request.startIndex}, '
          'endIndex=${request.endIndex}, childrenLength=${cat.children.length}, '
          'operationDepth=$_operationDepth'
        );
      }

      // Detect potential concurrent operation conflicts
      if (_operationDepth > 1) {
        final activeOps = _activeOperations.keys.where((key) => key != operationId).toList();
        // Log concurrent operation warning for debugging
        debugPrint('JustAudio: Concurrent operation detected - '
            'operation=$operationId, depth=$_operationDepth, '
            'activeOperations=$activeOps');
      }

      // Store context for error reporting and detailed state logging
      final childrenLength = cat.children.length;
      final shuffleOrderLength = cat.shuffleOrder.length;
      final removeCount = request.endIndex - request.startIndex;

      debugPrint('JustAudioBackground: removeRange pre-modification state - '
          'operationId=$operationId, id=${request.id}, startIndex=${request.startIndex}, '
          'endIndex=${request.endIndex}, removeCount=$removeCount, '
          'currentChildrenLength=$childrenLength, currentShuffleOrderLength=$shuffleOrderLength, '
          'currentChildrenTypes=[${cat.children.map((c) => c.runtimeType.toString()).join(', ')}], '
          'targetChildrenTypes=[${cat.children.sublist(request.startIndex, request.endIndex).map((c) => c.runtimeType.toString()).join(', ')}], '
          'requestShuffleOrder=[${request.shuffleOrder.join(', ')}], '
          'currentShuffleOrder=[${cat.shuffleOrder.join(', ')}]');

      try {
        cat.children.removeRange(request.startIndex, request.endIndex);
        cat.shuffleOrder
            .replaceRange(0, cat.shuffleOrder.length, request.shuffleOrder);

        // Log state after local modification
        debugPrint('JustAudioBackground: removeRange post-modification state - '
            'operationId=$operationId, id=${request.id}, '
            'newChildrenLength=${cat.children.length}, newShuffleOrderLength=${cat.shuffleOrder.length}, '
            'newChildrenTypes=[${cat.children.map((c) => c.runtimeType.toString()).join(', ')}], '
            'newShuffleOrder=[${cat.shuffleOrder.join(', ')}], '
            'removedFrom=${request.startIndex}, removedCount=$removeCount');

        _updateShuffleIndices();
        _broadcastStateIfActive();
        _updateQueue();

        debugPrint('JustAudioBackground: removeRange calling platform - '
            'operationId=$operationId, id=${request.id}, startIndex=${request.startIndex}, '
            'endIndex=${request.endIndex}, newLength=${cat.children.length}, '
            'platformRequestDetails={id: ${request.id}, startIndex: ${request.startIndex}, '
            'endIndex: ${request.endIndex}, shuffleOrderLength: ${request.shuffleOrder.length}}');

        // Enhanced platform operation with retry logic for IllegalArgumentException
        final result = await _retryBackgroundPlatformOperation(
          operation: () async {
            return await (await _player).concatenatingRemoveRange(request);
          },
          operationName: 'removeRange',
          context: {
            'operationId': operationId,
            'id': request.id,
            'startIndex': request.startIndex,
            'endIndex': request.endIndex,
            'childrenLength': childrenLength,
            'shuffleOrderLength': shuffleOrderLength,
            'removeCount': removeCount,
            'operationDepth': _operationDepth,
          },
          startTime: startTime,
        );

        final duration = DateTime.now().difference(startTime);
        debugPrint('JustAudioBackground: removeRange completed successfully - '
            'id=${request.id}, duration=${duration.inMilliseconds}ms');

        return result;
      } catch (e) {
        // Enhanced error context for debugging
        throw Exception(
          'ConcatenatingAudioSource.removeRange failed: '
          'id=${request.id}, startIndex=${request.startIndex}, '
          'endIndex=${request.endIndex}, childrenLength=$childrenLength, '
          'shuffleOrderLength=$shuffleOrderLength, '
          'removeCount=$removeCount, operationDepth=$_operationDepth, error=$e'
        );
      }
    } finally {
      // Clean up operation tracking
      _activeOperations.remove(operationId);
      _operationDepth--;

      final totalDuration = DateTime.now().difference(startTime);
      debugPrint('JustAudioBackground: removeRange operation cleanup - '
          'id=${request.id}, totalDuration=${totalDuration.inMilliseconds}ms, '
          'remainingDepth=$_operationDepth');
    }
  }

  Future<ConcatenatingMoveResponse> customConcatenatingMove(
      ConcatenatingMoveRequest request) async {
    final cat = _source!.findCat(request.id)!;
    cat.children
        .insert(request.newIndex, cat.children.removeAt(request.currentIndex));
    cat.shuffleOrder
        .replaceRange(0, cat.shuffleOrder.length, request.shuffleOrder);
    _updateShuffleIndices();
    _broadcastStateIfActive();
    _updateQueue();
    return await (await _player).concatenatingMove(request);
  }

  Future<SetAndroidAudioAttributesResponse> customSetAndroidAudioAttributes(
          SetAndroidAudioAttributesRequest request) async =>
      await (await _player).setAndroidAudioAttributes(request);

  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
      customSetAutomaticallyWaitsToMinimizeStalling(
              SetAutomaticallyWaitsToMinimizeStallingRequest request) async =>
          await (await _player)
              .setAutomaticallyWaitsToMinimizeStalling(request);

  Future<AndroidEqualizerBandSetGainResponse> customAndroidEqualizerBandSetGain(
          AndroidEqualizerBandSetGainRequest request) async =>
      await (await _player).androidEqualizerBandSetGain(request);

  Future<AndroidEqualizerGetParametersResponse>
      customAndroidEqualizerGetParameters(
              AndroidEqualizerGetParametersRequest request) async =>
          await (await _player).androidEqualizerGetParameters(request);

  Future<AndroidLoudnessEnhancerSetTargetGainResponse>
      customAndroidLoudnessEnhancerSetTargetGain(
              AndroidLoudnessEnhancerSetTargetGainRequest request) async =>
          await (await _player).androidLoudnessEnhancerSetTargetGain(request);

  Future<AudioEffectSetEnabledResponse> customAudioEffectSetEnabled(
          AudioEffectSetEnabledRequest request) async =>
      await (await _player).audioEffectSetEnabled(request);

  Future<SetAllowsExternalPlaybackResponse> customSetAllowsExternalPlayback(
          SetAllowsExternalPlaybackRequest request) async =>
      await (await _player).setAllowsExternalPlayback(request);

  Future<SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse>
      customSetCanUseNetworkResourcesForLiveStreamingWhilePaused(
              SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest
                  request) async =>
          await (await _player)
              .setCanUseNetworkResourcesForLiveStreamingWhilePaused(request);

  Future<SetPreferredPeakBitRateResponse> customSetPreferredPeakBitRate(
          SetPreferredPeakBitRateRequest request) async =>
      await (await _player).setPreferredPeakBitRate(request);

  void _updateQueue() {
    assert(sequence.every((source) => source.tag is MediaItem),
        'Error : When using just_audio_background, you should always set a MediaItem tag on every AudioSource. See AudioSource.uri documentation for more information.');
    queue.add(sequence.map((source) => source.tag as MediaItem).toList());
  }

  void _updateShuffleIndices() {
    _shuffleIndices = _source?.shuffleIndices ?? [];
    _effectiveIndices = _shuffleMode != AudioServiceShuffleMode.none
        ? _shuffleIndices
        : List.generate(sequence.length, (i) => i);
    _shuffleIndicesInv = List.filled(_effectiveIndices.length, 0);
    for (var i = 0; i < _effectiveIndices.length; i++) {
      _shuffleIndicesInv[_effectiveIndices[i]] = i;
    }
    _effectiveIndicesInv = _shuffleMode != AudioServiceShuffleMode.none
        ? _shuffleIndicesInv
        : List.generate(sequence.length, (i) => i);
  }

  List<IndexedAudioSourceMessage> get sequence => _source?.sequence ?? [];
  List<int> get shuffleIndices => _shuffleIndices;
  List<int> get effectiveIndices => _effectiveIndices;
  List<int> get shuffleIndicesInv => _shuffleIndicesInv;
  List<int> get effectiveIndicesInv => _effectiveIndicesInv;
  int? get nextIndex => getRelativeIndex(1);
  int? get previousIndex => getRelativeIndex(-1);
  bool get hasNext => nextIndex != null;
  bool get hasPrevious => previousIndex != null;

  int? getRelativeIndex(int offset) {
    if (currentQueue.isEmpty || index == null) return null;
    if (_repeatMode == AudioServiceRepeatMode.one) return index;
    if (effectiveIndices.isEmpty) return null;
    if (index! >= effectiveIndicesInv.length) return null;
    final invPos = effectiveIndicesInv[index!];
    var newInvPos = invPos + offset;
    if (newInvPos >= effectiveIndices.length || newInvPos < 0) {
      if (_repeatMode == AudioServiceRepeatMode.all) {
        newInvPos %= effectiveIndices.length;
      } else {
        return null;
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
      await skipToQueueItem(nextIndex!);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (hasPrevious) {
      await skipToQueueItem(previousIndex!);
    }
  }

  @override
  Future<void> play() async {
    if (_justAudioEvent.processingState == ProcessingStateMessage.completed) {
      await skipToQueueItem(0);
    }
    if (!_playing) {
      _updatePosition();
      customEvent.add(_PlayingEvent(_playing = true));
      _broadcastState();
      await (await _player).play(PlayRequest());
    }
  }

  @override
  Future<void> pause() async {
    _updatePosition();
    customEvent.add(_PlayingEvent(_playing = false));
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
    _updateShuffleIndices();
    _broadcastStateIfActive();
    (await _player).setShuffleMode(SetShuffleModeRequest(
        shuffleMode: ShuffleModeMessage.values[
            min(ShuffleModeMessage.values.length - 1, shuffleMode.index)]));
  }

  @override
  Future<void> stop() => _lock.synchronized(() async {
        final player = _playerCompleter.value;
        if (player == null) return;
        _updatePosition();
        customEvent.add(_PlayingEvent(_playing = false));
        _justAudioEvent = _justAudioEvent.copyWith(
          processingState: ProcessingStateMessage.idle,
        );
        _broadcastState();
        _playerCompleter = _ValueCompleter<AudioPlayerPlatform>();
        await _platform.disposePlayer(DisposePlayerRequest(id: player.id));
      });

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
    if (newPosition > currentMediaItem!.duration!) {
      newPosition = currentMediaItem!.duration!;
    }
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
          const Duration(seconds: 1), currentMediaItem!.duration!)
        ..start();
    }
  }

  void _broadcastStateIfActive() {
    if (_justAudioEvent.processingState != ProcessingStateMessage.idle) {
      _broadcastState();
    }
  }

  /// Broadcasts the current state to all clients.
  void _broadcastState() {
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
      processingState: _justAudioEvent.errorCode != null
          ? AudioProcessingState.error
          : const {
                ProcessingStateMessage.idle: AudioProcessingState.idle,
                ProcessingStateMessage.loading: AudioProcessingState.loading,
                ProcessingStateMessage.buffering:
                    AudioProcessingState.buffering,
                ProcessingStateMessage.ready: AudioProcessingState.ready,
                ProcessingStateMessage.completed:
                    AudioProcessingState.completed,
              }[_justAudioEvent.processingState] ??
              AudioProcessingState.idle,
      playing: _playing &&
          !{ProcessingStateMessage.idle, ProcessingStateMessage.completed}
              .contains(_justAudioEvent.processingState),
      updatePosition: currentPosition,
      bufferedPosition: _justAudioEvent.bufferedPosition,
      speed: _speed,
      queueIndex: _justAudioEvent.currentIndex,
      errorCode: _justAudioEvent.errorCode,
      errorMessage: _justAudioEvent.errorMessage,
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

  Future<void> start() async {
    _running = true;
    while (_running) {
      Duration newPosition = handler.currentPosition + positionInterval;
      if (newPosition < Duration.zero) newPosition = Duration.zero;
      if (newPosition > duration) newPosition = duration;
      handler.seek(newPosition);
      await Future<dynamic>.delayed(stepInterval);
    }
  }

  void stop() {
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
      for (final child in self.children) {
        final childIndices =
            child.shuffleIndices.map((i) => i + offset).toList();
        childIndicesList.add(childIndices);
        offset += childIndices.length;
      }
      final indices = <int>[];
      for (final index in self.shuffleOrder) {
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

@immutable
class TrackInfo {
  final int? index;
  final Duration? duration;

  const TrackInfo(this.index, this.duration);

  @override
  bool operator ==(Object other) =>
      other is TrackInfo && index == other.index && duration == other.duration;

  @override
  int get hashCode => Object.hash(index, duration);

  @override
  String toString() => '($index, $duration)';
}

/// Backwards compatible extensions on rxdart's ValueStream
extension _ValueStreamExtension<T> on ValueStream<T> {
  /// Backwards compatible version of valueOrNull.
  T? get nvalue => hasValue ? value : null;
}

class _PlayingEvent {
  final bool playing;

  const _PlayingEvent(this.playing);
}

class _ValueCompleter<T> {
  final _completer = Completer<T>();
  T? value;

  void complete(T value) {
    this.value = value;
    _completer.complete(value);
  }

  Future<T> get future => _completer.future;
}
