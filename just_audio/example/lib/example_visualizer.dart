// This example demonstrates the visualizer.
//
// To run:
//
// flutter run -t lib/example_visualizer.dart

import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_example/common.dart';
import 'package:rxdart/rxdart.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _player.playerStateStream.listen((state) {
        if (state.playing &&
            state.processingState != ProcessingState.idle &&
            state.processingState != ProcessingState.completed) {
          _player.startVisualizer(
              enableWaveform: true, enableFft: true, captureRate: 25000);
        } else {
          _player.stopVisualizer();
        }
      });
    }
    ambiguate(WidgetsBinding.instance)!.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
    ));
    _init();
  }

  Future<void> _init() async {
    // Inform the operating system of our app's audio attributes etc.
    // We pick a reasonable default for an app that plays speech.
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    // Listen to errors during playback.
    _player.playbackEventStream.listen((event) {},
        onError: (Object e, StackTrace stackTrace) {
      print('A stream error occurred: $e');
    });
    // Try to load audio from a source and catch any errors.
    try {
      await _player.setAudioSource(AudioSource.uri(Uri.parse(
          "https://files.freemusicarchive.org/storage-freemusicarchive-org/tracks/VW6RKBygup9QgTPkgSkUYccTLLIMKxuMR4si1oLh.mp3")));
    } catch (e) {
      print("Error loading audio source: $e");
    }
  }

  @override
  void dispose() {
    ambiguate(WidgetsBinding.instance)!.removeObserver(this);
    // Release decoders and buffers back to the operating system making them
    // available for other apps to use.
    _player.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Release the player's resources when not in use. We use "stop" so that
      // if the app resumes later, it will still remember what position to
      // resume from.
      _player.stop();
    }
  }

  /// Collects the data useful for displaying in a seek bar, using a handy
  /// feature of rx_dart to combine the 3 streams of interest into one.
  Stream<PositionData> get _positionDataStream =>
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
          _player.positionStream,
          _player.bufferedPositionStream,
          _player.durationStream,
          (position, bufferedPosition, duration) => PositionData(
              position, bufferedPosition, duration ?? Duration.zero));

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Display the FFT visualizer widget
              if (!kIsWeb)
                Container(
                  height: 50.0,
                  padding: const EdgeInsets.all(16.0),
                  width: double.maxFinite,
                  child: StreamBuilder<VisualizerFftCapture>(
                    stream: _player.visualizerFftStream,
                    builder: (context, snapshot) {
                      if (snapshot.data == null) return const SizedBox();
                      return FftVisualizerWidget(snapshot.data!);
                    },
                  ),
                ),
              // Display the waveform visualizer widget
              if (!kIsWeb)
                Container(
                  height: 50.0,
                  padding: const EdgeInsets.all(16.0),
                  width: double.maxFinite,
                  child: StreamBuilder<VisualizerWaveformCapture>(
                    stream: _player.visualizerWaveformStream,
                    builder: (context, snapshot) {
                      if (snapshot.data == null) return const SizedBox();
                      return WaveformVisualizerWidget(snapshot.data!);
                    },
                  ),
                ),
              // Display play/pause button and volume/speed sliders.
              ControlButtons(_player),
              // Display seek bar. Using StreamBuilder, this widget rebuilds
              // each time the position, buffered position or duration changes.
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
            ],
          ),
        ),
      ),
    );
  }
}

class WaveformVisualizerWidget extends StatelessWidget {
  final VisualizerWaveformCapture capture;

  const WaveformVisualizerWidget(this.capture, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: CustomPaint(
        painter: WaveformVisualizerPainter(capture),
      ),
    );
  }
}

class WaveformVisualizerPainter extends CustomPainter {
  final VisualizerWaveformCapture capture;
  final Paint barPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0
    ..color = Colors.blue;

  WaveformVisualizerPainter(this.capture);

  @override
  void paint(Canvas canvas, Size size) {
    int getSample(double d) {
      final i = d.toInt();
      if (i >= 0 && i < capture.data.length) {
        return capture.data[i] - 128;
      } else {
        return 0;
      }
    }

    const barCount = 120;
    final barWidth = size.width / barCount;
    final midY = size.height / 2;
    for (var barX = 0.0; barX < size.width; barX += barWidth) {
      final sample = getSample(barX);
      canvas.drawLine(
          Offset(barX.toDouble(), midY),
          Offset(barX.toDouble(), midY - sample * size.height / 2 / 128),
          barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant WaveformVisualizerPainter oldDelegate) {
    return true;
  }
}

class FftVisualizerWidget extends StatelessWidget {
  final VisualizerFftCapture capture;

  const FftVisualizerWidget(this.capture, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: CustomPaint(
        painter: FftVisualizerPainter(capture),
      ),
    );
  }
}

class FftVisualizerPainter extends CustomPainter {
  final VisualizerFftCapture capture;

  FftVisualizerPainter(this.capture);

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 16;
    const minDbThresh = 5;

    final length = capture.length;
    final barWidth = size.width / barCount;
    final barPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = barWidth * 0.8
      ..color = Colors.blue;
    double log10(num x) => log(x) / ln10;
    for (var i = 0; i < barCount; i++) {
      final magnitude = pow(capture.getMagnitude(i * length ~/ barCount), 2);
      final barX = barWidth * (i + 0.5);
      final db = magnitude < 1.0 ? 0.0 : 10.0 * log10(magnitude);
      canvas.drawLine(Offset(barX, size.height),
          Offset(barX, size.height - (db - minDbThresh)), barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant FftVisualizerPainter oldDelegate) {
    return true;
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
        // Opens volume slider dialog
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

        /// This StreamBuilder rebuilds whenever the player state changes, which
        /// includes the playing/paused state and also the
        /// loading/buffering/ready state. Depending on the state we show the
        /// appropriate button or loading indicator.
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
        // Opens speed slider dialog
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
