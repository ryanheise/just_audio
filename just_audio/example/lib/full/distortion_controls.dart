import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class DistortionControls extends StatelessWidget {
  final DarwinDistortion distortion;

  const DistortionControls(this.distortion, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Distortion", style: Theme.of(context).textTheme.headline3),
        const SizedBox(height: 10),
        Row(
          children: [
            StreamBuilder<bool>(
              stream: distortion.enabledStream,
              builder: (context, snap) => Switch(
                value: snap.data ?? false,
                onChanged: (change) async {
                  await distortion.setEnabled(change);
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
            StreamBuilder<DarwinDistortionPreset>(
              stream: distortion.presetStream,
              builder: (context, AsyncSnapshot<DarwinDistortionPreset> snap) {
                return DropdownButton<DarwinDistortionPreset>(
                  value: snap.data,
                  items: DarwinDistortionPreset.values
                      .map<DropdownMenuItem<DarwinDistortionPreset>>(
                        (e) => DropdownMenuItem(value: e, child: Text(e.name)),
                      )
                      .toList(),
                  onChanged: (DarwinDistortionPreset? change) async {
                    if (change != null) {
                      await distortion.setPreset(change);
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
        const Text("Distortion Gain"),
        StreamBuilder<double>(
          stream: distortion.preGainMixStream,
          builder: (context, snap) {
            return Slider(
              value: snap.data ?? distortion.preGain,
              min: 0,
              max: 100,
              onChanged: (change) async {
                await distortion.setPreGain(change);
              },
            );
          },
        ),
        const SizedBox(height: 16),
        const Text("Distortion Wet Dry Mix"),
        StreamBuilder<double>(
          stream: distortion.wetDryMixStream,
          builder: (context, snap) {
            return Slider(
              min: 0,
              max: 100,
              value: snap.data ?? distortion.wetDryMix,
              onChanged: (change) async {
                await distortion.setWetDryMix(change);
              },
            );
          },
        ),
      ],
    );
  }
}
