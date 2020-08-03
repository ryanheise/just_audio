import 'dart:math';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _volumeSubject = BehaviorSubject.seeded(1.0);
  final _speedSubject = BehaviorSubject.seeded(1.0);
  AudioPlayer _player;
  ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(children: [
    LoopingAudioSource(
      count: 2,
      child: ClippingAudioSource(
        start: Duration(seconds: 60),
        end: Duration(seconds: 65),
        child: AudioSource.uri(Uri.parse(
            "https://s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3")),
        tag: AudioMetadata(
          album: "Science Friday",
          title: "A Salute To Head-Scratching Science (5 seconds)",
        ),
      ),
    ),
    AudioSource.uri(
      Uri.parse(
          "https://s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3"),
      tag: AudioMetadata(
        album: "Science Friday",
        title: "A Salute To Head-Scratching Science",
      ),
    ),
    AudioSource.uri(
      Uri.parse("https://s3.amazonaws.com/scifri-segments/scifri201711241.mp3"),
      tag: AudioMetadata(
        album: "Science Friday",
        title: "From Cat Rheology To Operatic Incompetence",
      ),
    ),
  ]);

  List<IndexedAudioSource> get _sequence => _playlist.sequence;

  List<AudioMetadata> get _metadataSequence =>
      _sequence.map((s) => s.tag as AudioMetadata).toList();

  @override
  void initState() {
    super.initState();
    AudioPlayer.setIosCategory(IosCategory.playback);
    _player = AudioPlayer();
    _loadAudio();
  }

  _loadAudio() async {
    try {
      await _player.load(_playlist);
    } catch (e) {
      // catch load errors: 404 url, wrong url ...
      print("$e");
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Audio Player Demo'),
        ),
        body: Center(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              StreamBuilder<int>(
                stream: _player.currentIndexStream,
                builder: (context, snapshot) {
                  final index = snapshot.data ?? 0;
                  final metadata = _metadataSequence[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(metadata.album ?? '',
                          style: Theme.of(context).textTheme.headline6),
                      Text(metadata.title ?? ''),
                    ],
                  );
                },
              ),
              StreamBuilder<PlayerState>(
                stream: _player.playerStateStream,
                builder: (context, snapshot) {
                  final playerState = snapshot.data;
                  final processingState = playerState?.processingState;
                  final playing = playerState?.playing;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (processingState == ProcessingState.buffering)
                        Container(
                          margin: EdgeInsets.all(8.0),
                          width: 64.0,
                          height: 64.0,
                          child: CircularProgressIndicator(),
                        )
                      else if (playing != true)
                        IconButton(
                          icon: Icon(Icons.play_arrow),
                          iconSize: 64.0,
                          onPressed: _player.play,
                        )
                      else if (processingState != ProcessingState.completed)
                        IconButton(
                          icon: Icon(Icons.pause),
                          iconSize: 64.0,
                          onPressed: _player.pause,
                        )
                      else
                        IconButton(
                          icon: Icon(Icons.replay),
                          iconSize: 64.0,
                          onPressed: () =>
                              _player.seek(Duration.zero, index: 0),
                        ),
                    ],
                  );
                },
              ),
              Text("Track position"),
              StreamBuilder<Duration>(
                stream: _player.durationStream,
                builder: (context, snapshot) {
                  final duration = snapshot.data ?? Duration.zero;
                  return StreamBuilder<Duration>(
                    stream: _player.positionStream,
                    builder: (context, snapshot) {
                      var position = snapshot.data ?? Duration.zero;
                      if (position > duration) {
                        position = duration;
                      }
                      return SeekBar(
                        duration: duration,
                        position: position,
                        onChangeEnd: (newPosition) {
                          _player.seek(newPosition);
                        },
                      );
                    },
                  );
                },
              ),
              Text("Volume"),
              StreamBuilder<double>(
                stream: _volumeSubject.stream,
                builder: (context, snapshot) => Slider(
                  divisions: 20,
                  min: 0.0,
                  max: 2.0,
                  value: snapshot.data ?? 1.0,
                  onChanged: (value) {
                    _volumeSubject.add(value);
                    _player.setVolume(value);
                  },
                ),
              ),
              Text("Speed"),
              StreamBuilder<double>(
                stream: _speedSubject.stream,
                builder: (context, snapshot) => Slider(
                  divisions: 10,
                  min: 0.5,
                  max: 1.5,
                  value: snapshot.data ?? 1.0,
                  onChanged: (value) {
                    _speedSubject.add(value);
                    _player.setSpeed(value);
                  },
                ),
              ),
              Row(
                children: [
                  StreamBuilder<LoopMode>(
                    stream: _player.loopModeStream,
                    builder: (context, snapshot) {
                      final loopMode = snapshot.data ?? LoopMode.off;
                      const icons = [
                        Icon(Icons.repeat, color: Colors.grey),
                        Icon(Icons.repeat, color: Colors.orange),
                        Icon(Icons.repeat_one, color: Colors.orange),
                      ];
                      const cycleModes = [
                        LoopMode.off,
                        LoopMode.all,
                        LoopMode.one,
                      ];
                      final index = cycleModes.indexOf(loopMode);
                      return IconButton(
                        icon: icons[index],
                        onPressed: () {
                          _player.setLoopMode(cycleModes[
                              (cycleModes.indexOf(loopMode) + 1) %
                                  cycleModes.length]);
                        },
                      );
                    },
                  ),
                  Expanded(
                    child: Text(
                      "Playlist",
                      style: Theme.of(context).textTheme.headline6,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  StreamBuilder<bool>(
                    stream: _player.shuffleModeEnabledStream,
                    builder: (context, snapshot) {
                      final shuffleModeEnabled = snapshot.data ?? false;
                      return IconButton(
                        icon: shuffleModeEnabled
                            ? Icon(Icons.shuffle, color: Colors.orange)
                            : Icon(Icons.shuffle, color: Colors.grey),
                        onPressed: () {
                          _player.setShuffleModeEnabled(!shuffleModeEnabled);
                        },
                      );
                    },
                  ),
                ],
              ),
              Expanded(
                child: StreamBuilder<int>(
                  stream: _player.currentIndexStream,
                  builder: (context, snapshot) {
                    final currentIndex = snapshot.data ?? 0;
                    return ListView.builder(
                      itemCount: _metadataSequence.length,
                      itemBuilder: (context, index) => Material(
                        color:
                            index == currentIndex ? Colors.grey.shade300 : null,
                        child: ListTile(
                          title: Text(_metadataSequence[index].title),
                          onTap: () {
                            _player.seek(Duration.zero, index: index);
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SeekBar extends StatefulWidget {
  final Duration duration;
  final Duration position;
  final ValueChanged<Duration> onChanged;
  final ValueChanged<Duration> onChangeEnd;

  SeekBar({
    @required this.duration,
    @required this.position,
    this.onChanged,
    this.onChangeEnd,
  });

  @override
  _SeekBarState createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double _dragValue;

  @override
  Widget build(BuildContext context) {
    return Slider(
      min: 0.0,
      max: widget.duration.inMilliseconds.toDouble(),
      value: min(_dragValue ?? widget.position.inMilliseconds.toDouble(),
          widget.duration.inMilliseconds.toDouble()),
      onChanged: (value) {
        setState(() {
          _dragValue = value;
        });
        if (widget.onChanged != null) {
          widget.onChanged(Duration(milliseconds: value.round()));
        }
      },
      onChangeEnd: (value) {
        if (widget.onChangeEnd != null) {
          widget.onChangeEnd(Duration(milliseconds: value.round()));
        }
        _dragValue = null;
      },
    );
  }
}

class AudioMetadata {
  final String album;
  final String title;

  AudioMetadata({this.album, this.title});
}
