import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class DelayControls extends StatelessWidget {
  final DarwinDelay delay;

  const DelayControls(this.delay, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Delay", style: Theme.of(context).textTheme.headline3),
        const SizedBox(height: 10),
        Row(
          children: [
            StreamBuilder<bool>(
              stream: delay.enabledStream,
              builder: (context, snap) => Switch(
                value: snap.data ?? false,
                onChanged: (change) async {
                  await delay.setEnabled(change);
                },
              ),
            ),
            const SizedBox(width: 10),
            const Text("Activate"),
          ],
        ),
        const SizedBox(height: 16),
        const Text("Delay Time"),
        StreamBuilder<double>(
          stream: delay.secondsDelayTimeStream,
          builder: (context, snap) {
            return Slider(
              value: snap.data ?? delay.secondsDelayTime,
              min: 0,
              max: 2,
              onChanged: (change) async {
                await delay.setDelayTime(change);
              },
            );
          },
        ),
        const SizedBox(height: 16),
        const Text("Delay Low Pass Cutoff"),
        StreamBuilder<double>(
          stream: delay.lowPassCutoffHzStream,
          builder: (context, snap) {
            return Slider(
              value: snap.data ?? delay.lowPassCutoffHz,
              min: 10,
              max: 15000 * 2,
              divisions: 10,
              onChanged: (change) async {
                await delay.setLowPassCutoffHz(change);
              },
            );
          },
        ),
        const SizedBox(height: 16),
        const Text("Delay Feedback"),
        StreamBuilder<double>(
          stream: delay.feedbackPercentStream,
          builder: (context, snap) {
            return Slider(
              value: snap.data ?? delay.feedbackPercent,
              min: -100,
              max: 100,
              onChanged: (change) async {
                await delay.setFeedbackPercent(change);
              },
            );
          },
        ),
        const SizedBox(height: 16),
        const Text("Distortion Wet Dry Mix"),
        StreamBuilder<double>(
          stream: delay.wetDryMixStream,
          builder: (context, snap) {
            return Slider(
              min: 0,
              max: 100,
              value: snap.data ?? delay.wetDryMixPercent,
              onChanged: (change) async {
                await delay.setWetDryMixPercent(change);
              },
            );
          },
        ),
      ],
    );
  }
}
