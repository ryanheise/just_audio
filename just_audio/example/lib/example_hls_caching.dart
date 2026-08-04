// ignore_for_file: use_build_context_synchronously

import 'media_kit_stub.dart' if (dart.library.io) 'media_kit_impl.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_example/common.dart';
import 'package:rxdart/rxdart.dart';

void main() {
  initMediaKit();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HlsCachingDemoPage(),
    );
  }
}

class HlsCachingDemoPage extends StatefulWidget {
  const HlsCachingDemoPage({Key? key}) : super(key: key);

  @override
  HlsCachingDemoPageState createState() => HlsCachingDemoPageState();
}

class HlsCachingDemoPageState extends State<HlsCachingDemoPage>
    with WidgetsBindingObserver {
  final _player = AudioPlayer();

  final _hlsAudioSource = HlsPrecachingAudioSource(
    Uri.parse(
        'https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8'),
    headers: {'User-Agent': 'MyAudioApp/1.0'},
  );

  @override
  void initState() {
    super.initState();
    ambiguate(WidgetsBinding.instance)!.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
    ));
    _init();
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    _player.errorStream.listen((e) {
      print('A stream error occurred: $e');
    });

    try {
      // Check if already downloaded
      await _hlsAudioSource.isStreamDownloaded();

      // Set the audio source (will use cached version if available)
      await _player.setAudioSource(_hlsAudioSource);
    } on PlayerException catch (e) {
      print("Error loading audio source: $e");
    }
  }

  @override
  void dispose() {
    ambiguate(WidgetsBinding.instance)!.removeObserver(this);
    _player.dispose();
    _hlsAudioSource.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _player.stop();
    }
  }

  /// Combines position, download progress, and duration into one stream
  Stream<PositionData> get _positionDataStream =>
      Rx.combineLatest3<Duration, double, Duration?, PositionData>(
          _player.positionStream,
          _hlsAudioSource.downloadProgressStream,
          _player.durationStream,
          (position, downloadProgress, reportedDuration) {
        final duration = reportedDuration ?? Duration.zero;
        final bufferedPosition = duration * downloadProgress;
        return PositionData(position, bufferedPosition, duration);
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HLS Audio Caching Example'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Download controls
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'HLS Download Controls',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),

                    // Download status
                    StreamBuilder<double>(
                      stream: _hlsAudioSource.downloadProgressStream,
                      builder: (context, snapshot) {
                        final progress = snapshot.data ?? 0.0;
                        final isDownloaded = progress >= 1.0;
                        final isDownloading = _hlsAudioSource.isDownloading;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isDownloaded
                                  ? 'Status: Downloaded ✅'
                                  : isDownloading
                                      ? 'Status: Downloading... ${(progress * 100).toStringAsFixed(1)}%'
                                      : 'Status: Not Downloaded',
                              style: TextStyle(
                                color: isDownloaded ? Colors.green : null,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (isDownloading) ...[
                              LinearProgressIndicator(value: progress),
                              const SizedBox(height: 8),
                            ],
                          ],
                        );
                      },
                    ),

                    // Download buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _downloadHLS,
                            child: const Text('Download'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _cancelDownload,
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _clearCache,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Delete'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Player controls
            ControlButtons(_player),

            // Seek bar with download progress
            StreamBuilder<PositionData>(
              stream: _positionDataStream,
              builder: (context, snapshot) {
                final positionData = snapshot.data;
                return SeekBar(
                  duration: positionData?.duration ?? Duration.zero,
                  position: positionData?.position ?? Duration.zero,
                  bufferedPosition:
                      positionData?.bufferedPosition ?? Duration.zero,
                  onChangeEnd: _player.seek,
                );
              },
            ),

            const SizedBox(height: 16),

            // Download management
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Download Management',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: _listAllDownloads,
                          child: const Text('List Downloads'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _clearAllDownloads,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Clear All'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadHLS() async {
    try {
      print('Starting HLS download...');
      final success = await _hlsAudioSource.download();
      if (success) {
        print('HLS download started successfully');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download completed')),
        );
      } else {
        print('Failed to start HLS download');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start download')),
        );
      }
    } catch (e) {
      print('Error starting download: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _cancelDownload() async {
    try {
      final cancelled = await _hlsAudioSource.cancelDownload();
      if (cancelled) {
        print('Download cancelled');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download cancelled')),
        );
      }
    } catch (e) {
      print('Error cancelling download: $e');
    }
  }

  Future<void> _clearCache() async {
    try {
      final cleared = await _hlsAudioSource.clearCache();
      if (cleared) {
        print('Cache cleared');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cache cleared')),
        );
      }
    } catch (e) {
      print('Error clearing cache: $e');
    }
  }

  Future<void> _listAllDownloads() async {
    try {
      final downloads = await HlsPrecachingAudioSource.listAllDownloads();
      print('All downloads: $downloads');

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Downloaded Content'),
          content: downloads.isEmpty
              ? const Text('No downloads found')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: downloads.entries
                      .map((entry) => Text('${entry.key}: ${entry.value}'))
                      .toList(),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      print('Error listing downloads: $e');
    }
  }

  Future<void> _clearAllDownloads() async {
    try {
      final cleared = await HlsPrecachingAudioSource.clearAllDownloads();
      if (cleared) {
        print('All downloads cleared');
        _hlsAudioSource.clearCache();
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All downloads cleared')),
        );
      }
    } catch (e) {
      print('Error clearing all downloads: $e');
    }
  }
}

/// Displays the play/pause button and volume/speed sliders.
class ControlButtons extends StatelessWidget {
  final AudioPlayer player;

  const ControlButtons(this.player, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Volume control
        IconButton(
          icon: const Icon(Icons.volume_up),
          onPressed: () {
            showSliderDialog(
              context: context,
              title: "Adjust volume",
              divisions: 10,
              min: 0.0,
              max: 1.0,
              value: player.volume,
              stream: player.volumeStream,
              onChanged: player.setVolume,
            );
          },
        ),

        // Play/pause button with loading indicator
        StreamBuilder<PlayerState>(
          stream: player.playerStateStream,
          builder: (context, snapshot) {
            final playerState = snapshot.data;
            final processingState = playerState?.processingState;
            final playing = playerState?.playing;
            if (processingState == ProcessingState.loading ||
                processingState == ProcessingState.buffering) {
              return Container(
                margin: const EdgeInsets.all(8.0),
                width: 64.0,
                height: 64.0,
                child: const CircularProgressIndicator(),
              );
            } else if (playing != true) {
              return IconButton(
                icon: const Icon(Icons.play_arrow),
                iconSize: 64.0,
                onPressed: player.play,
              );
            } else if (processingState != ProcessingState.completed) {
              return IconButton(
                icon: const Icon(Icons.pause),
                iconSize: 64.0,
                onPressed: player.pause,
              );
            } else {
              return IconButton(
                icon: const Icon(Icons.replay),
                iconSize: 64.0,
                onPressed: () => player.seek(Duration.zero),
              );
            }
          },
        ),

        // Speed control
        StreamBuilder<double>(
          stream: player.speedStream,
          builder: (context, snapshot) => IconButton(
            icon: Text("${snapshot.data?.toStringAsFixed(1)}x",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              showSliderDialog(
                context: context,
                title: "Adjust speed",
                divisions: 10,
                min: 0.5,
                max: 1.5,
                value: player.speed,
                stream: player.speedStream,
                onChanged: player.setSpeed,
              );
            },
          ),
        ),
      ],
    );
  }
}
