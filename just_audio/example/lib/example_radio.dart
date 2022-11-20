// This is a minimal example demonstrating live streaming.
//
// To run:
//
// flutter run -t lib/example_radio.dart

import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_example/common.dart';

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
    _setStation(0);
  }

  int _currentIndex = 0;
  Future<void> _setStation(int index) async {
    setState(() => _currentIndex = index);
    print('XXXX _currentIndex = $_currentIndex');
    final String station = stations[_currentIndex];
    final String stationUrl = stationUrls[_currentIndex];
    try {
      print('XXXX loading station $station');
      print('XXXX url: $stationUrl');
      await _player.setAudioSource(AudioSource.uri(Uri.parse(stationUrl)));
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

  @override
  Widget build(BuildContext context) {
    final String station = stations[_currentIndex];
    final String stationUrl = stationUrls[_currentIndex];
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: SizedBox(
            width: double.maxFinite,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                StreamBuilder<IcyMetadata?>(
                  stream: _player.icyMetadataStream,
                  builder: (context, snapshot) {
                    final metadata = snapshot.data;
                    final title = metadata?.info?.title ?? '';
                    final url = metadata?.info?.url;
                    return Column(
                      children: [
                        SelectableText('Station: $station'),
                        SelectableText('StationUrl: $stationUrl'),
                        if (url == null) const Text('ArtworkUrl: null'),
                        if (url != null) Text('ArtworkUrl: $url'),
                        if (url != null)
                          Image.network(
                            url,
                            errorBuilder: (context, error, stackTrace) =>
                                Text('Invalid artwork url: "$url"'),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(title,
                              style: Theme.of(context).textTheme.headline6),
                        ),
                      ],
                    );
                  },
                ),
                // Display play/pause button and volume/speed sliders.
                ControlButtons(_player, _currentIndex),
                Flexible(child: _buildListview()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListview() {
    return ListView.builder(
        itemCount: stations.length,
        itemBuilder: (context, index) {
          return ListTile(
              selected: _currentIndex == index,
              selectedTileColor: Colors.grey.shade400,
              tileColor: Colors.grey.shade200,
              key: ValueKey(index),
              title: Text(stations[index]),
              onTap: () => _setStation(index));
        });
  }
}

/// Displays the play/pause button and volume/speed sliders.
class ControlButtons extends StatelessWidget {
  final AudioPlayer player;
  final int? currentIndex;

  const ControlButtons(this.player, this.currentIndex, {Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
              return Column(
                children: [
                  if (currentIndex != null)
                    IconButton(
                      icon: const Icon(Icons.play_arrow),
                      iconSize: 64.0,
                      onPressed: player.play,
                    ),
                ],
              );
            } else if (processingState != ProcessingState.completed) {
              return Column(
                children: [
                  if (currentIndex != null)
                    IconButton(
                      icon: const Icon(Icons.pause),
                      iconSize: 64.0,
                      onPressed: player.pause,
                    ),
                ],
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

final stations = [
  'radioparadise',
  'WETF',
  'KCSM',
  'WBGO',
  'WDCB',
  'WICN',
  'WZUM',
  'KEXP',
  'WXPN',
];

final stationUrls = [
  'https://stream-uk1.radioparadise.com/aac-320',
  'https://ssl-proxy.icastcenter.com/get.php?type=Icecast&server=199.180.72.2&port=9007&mount=/stream&data=mp3',
  'https://ice5.securenetsystems.net/KCSM',
  'https://wbgo.streamguys1.com/wbgo128',
  'https://wdcb-ice.streamguys1.com/wdcb128',
  'https://wicn-ice.streamguys1.com/live-mp3',
  'https://pubmusic.streamguys1.com/wzum-aac',
  'https://kexp-mp3-128.streamguys1.com/kexp128.mp3?awparams=companionAds%3Afalse',
  'https://wxpnhi.xpn.org/xpnhi',
];
