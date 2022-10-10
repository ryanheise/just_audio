import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_example/example_effects.dart';

class EqualizerControlsCard extends StatelessWidget {
  final Equalizer equalizer;

  const EqualizerControlsCard({required this.equalizer, Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 500,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Equalizer", style: Theme.of(context).textTheme.headline3),
          const SizedBox(height: 10),
          StreamBuilder<bool>(
            stream: equalizer.enabledStream,
            builder: (context, snapshot) {
              final enabled = snapshot.data ?? false;
              return SwitchListTile(
                title: const Text('Equalizer'),
                value: enabled,
                onChanged: equalizer.setEnabled,
              );
            },
          ),
          Expanded(
            child: EqualizerControls(equalizer: equalizer),
          ),
        ],
      ),
    );
  }
}
