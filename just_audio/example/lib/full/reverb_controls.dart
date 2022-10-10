import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class ReverbControls extends StatelessWidget {
  final DarwinReverb reverb;

  const ReverbControls(this.reverb, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Reverb", style: Theme.of(context).textTheme.headline3),
        const SizedBox(height: 10),
        Row(
          children: [
            StreamBuilder<bool>(
              stream: reverb.enabledStream,
              builder: (context, snap) => Switch(
                value: snap.data ?? false,
                onChanged: (change) async {
                  await reverb.setEnabled(change);
                },
              ),
            ),
            const SizedBox(width: 10),
            const Text("Activate"),
          ],
        ),
        Row(
          children: [
            const SizedBox(width: 16),
            StreamBuilder<DarwinReverbPreset>(
              stream: reverb.presetStream,
              builder: (context, AsyncSnapshot<DarwinReverbPreset> snap) {
                return DropdownButton<DarwinReverbPreset>(
                  value: snap.data,
                  items: DarwinReverbPreset.values
                      .map<DropdownMenuItem<DarwinReverbPreset>>(
                        (e) => DropdownMenuItem(value: e, child: Text(e.name)),
                      )
                      .toList(),
                  onChanged: (DarwinReverbPreset? change) async {
                    if (change != null) {
                      await reverb.setPreset(change);
                    }
                  },
                );
              },
            ),
            const SizedBox(width: 10),
            const Text("Preset"),
          ],
        ),
        const SizedBox(height: 16),
        const Text("Reverb Wet Dry Mix"),
        StreamBuilder<double>(
          stream: reverb.wetDryMixStream,
          builder: (context, snap) {
            return Slider(
              min: 0,
              max: 100,
              value: snap.data ?? reverb.wetDryMix,
              onChanged: (change) async {
                await reverb.setWetDryMix(change);
              },
            );
          },
        ),
      ],
    );
  }
}
