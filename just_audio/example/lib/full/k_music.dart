import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_example/common.dart';
import 'package:just_audio_example/full/delay_controls.dart';
import 'package:just_audio_example/full/distortion_controls.dart';
import 'package:just_audio_example/full/equalizer_controls.dart';
import 'package:just_audio_example/full/reverb_controls.dart';
import 'package:just_audio_example/full/write_to_file_controls.dart';
import 'package:rxdart/rxdart.dart';

void main() => runApp(const KMusicApp());

/// An iOS-focused example of usage for
/// effects
/// mixer
/// write to output file
/// multiple tracks
class KMusicApp extends StatefulWidget {
  const KMusicApp({Key? key}) : super(key: key);

  @override
  KMusicState createState() => KMusicState();
}

class KMusicState extends State<KMusicApp> with WidgetsBindingObserver {
  // Distortion
  final distortion = DarwinDistortion(
    enabled: false,
    preset: DarwinDistortionPreset.drumsBitBrush,
  );

  // Reverb
  final reverb = DarwinReverb(
    preset: DarwinReverbPreset.largeHall2,
    enabled: false,
    wetDryMix: 0,
  );

  // Delay
  final delay = DarwinDelay(
    enabled: false,
  );

  final _equalizer = Equalizer(
    darwinMessageParameters: DarwinEqualizerParametersMessage(
      minDecibels: -26.0,
      maxDecibels: 24.0,
      bands: [
        DarwinEqualizerBandMessage(index: 0, centerFrequency: 60, gain: 0),
        DarwinEqualizerBandMessage(index: 1, centerFrequency: 230, gain: 0),
        DarwinEqualizerBandMessage(index: 2, centerFrequency: 910, gain: 0),
        DarwinEqualizerBandMessage(index: 3, centerFrequency: 3600, gain: 0),
        DarwinEqualizerBandMessage(index: 4, centerFrequency: 14000, gain: 0),
      ],
    ),
  );

  late final _player = AudioPlayer(
    audioPipeline: AudioPipeline(
      darwinAudioEffects: [_equalizer],
    ),
  );

  final _metronomePlayer = AudioPlayer();

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
    // Inform the operating system of our app's audio attributes etc.
    // We pick a reasonable default for an app that plays speech.
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    // Listen to errors during playback.
    _player.playbackEventStream.listen((event) {
      print(event.toString());
    }, onError: (Object e, StackTrace stackTrace) {
      print('A stream error occurred: $e');
      print(stackTrace);
    });
    // Try to load audio from a source and catch any errors.
    try {
      await _player.setAudioSource(
        ConcatenatingAudioSource(
          children: [
            AudioSource.uri(
              Uri.parse(
                "asset:///audio/assets_mp3_dua_lipa_dont_start_now.mp3",
              ),
              effects: [
                distortion,
                reverb,
                delay,
              ],
            ),
          ],
        ),
      );

      final value = await rootBundle.loadBuffer("audio/metronome.mp3");

      print(value.length);
      await _metronomePlayer.setAudioSource(LoopingAudioSource(
        child: AudioSource.uri(
          Uri.parse("asset:///audio/metronome.mp3"),
        ),
        count: 300,
      ));
    } catch (e) {
      print("Error loading audio source: $e");
    }
  }

  @override
  void dispose() {
    ambiguate(WidgetsBinding.instance)!.removeObserver(this);
    _player.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _player.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: CustomScrollView(
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: BasicPlayerInfoHeaderDelegate(
                    player: _player,
                  ),
                ),
                SliverList(
                  delegate: SliverChildListDelegate(
                    [
                      PaddedCard(
                        child: DistortionControls(distortion),
                      ),
                      const SizedBox(height: 20),
                      PaddedCard(
                        child: ReverbControls(reverb),
                      ),
                      const SizedBox(height: 20),
                      PaddedCard(
                        child: DelayControls(delay),
                      ),
                      const SizedBox(height: 20),
                      PaddedCard(
                        child: WriteToFileControls(player: _player),
                      ),
                      const SizedBox(height: 20),
                      PaddedCard(
                        child: EqualizerControlsCard(equalizer: _equalizer),
                      ),
                      PaddedCard(
                        child: Column(
                          children: [
                            Text("Multiple tracks",
                                style: Theme.of(context).textTheme.headline3),
                            const SizedBox(height: 10),
                            ControlButtons(_metronomePlayer)
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PaddedCard extends StatelessWidget {
  final Widget child;

  const PaddedCard({required this.child, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(10), child: child),
    );
  }
}

class BasicPlayerInfoHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final AudioPlayer player;

  BasicPlayerInfoHeaderDelegate({
    required this.player,
    this.height = 150,
  });

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return BasicPlayerInfo(player: player);
  }

  @override
  double get maxExtent => height;

  @override
  double get minExtent => height;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return false;
  }
}

class BasicPlayerInfo extends StatelessWidget {
  final AudioPlayer player;

  /// Collects the data useful for displaying in a seek bar, using a handy
  /// feature of rx_dart to combine the 3 streams of interest into one.
  late final Stream<PositionData> positionDataStream =
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
          player.positionStream,
          player.bufferedPositionStream,
          player.durationStream,
          (position, bufferedPosition, duration) => PositionData(
              position, bufferedPosition, duration ?? Duration.zero));

  BasicPlayerInfo({
    required this.player,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Display play/pause button and volume/speed sliders.
          ControlButtons(player),
          // Display seek bar. Using StreamBuilder, this widget rebuilds
          // each time the position, buffered position or duration changes.
          StreamBuilder<PositionData>(
            stream: positionDataStream,
            initialData: PositionData(
              player.position,
              player.bufferedPosition,
              player.duration ?? Duration.zero,
            ),
            builder: (context, snapshot) {
              final positionData = snapshot.requireData;

              return SeekBar(
                duration: positionData.duration,
                position: positionData.position,
                bufferedPosition: positionData.bufferedPosition,
                onChangeEnd: player.seek,
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Displays the play/pause button and volume/speed sliders.
class ControlButtons extends StatelessWidget {
  final AudioPlayer player;

  const ControlButtons(this.player, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        StreamBuilder<PlayerState>(
          stream: player.playerStateStream,
          builder: (context, snapshot) {
            final playerState = snapshot.data;
            final processingState = playerState?.processingState;
            final playing = playerState?.playing ?? false;
            if (processingState == ProcessingState.loading ||
                processingState == ProcessingState.buffering) {
              return Container(
                margin: const EdgeInsets.all(8.0),
                width: 64.0,
                height: 64.0,
                child: const CircularProgressIndicator(),
              );
            } else if (!playing) {
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
      ],
    );
  }
}
