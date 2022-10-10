import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

class WriteToFileControls extends StatelessWidget {
  final AudioPlayer player;
  const WriteToFileControls({
    Key? key,
    required this.player,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Write to file", style: Theme.of(context).textTheme.headline3),
        const SizedBox(height: 10),
        Row(
          children: [
            StreamBuilder<bool>(
              stream:
                  player.outputAbsolutePathStream.map((event) => event != null),
              builder: (context, snap) => Switch(
                value: snap.data ?? false,
                onChanged: (change) async {
                  if (change) {
                    await player.writeOutputToFile();
                  } else {
                    await player.stopWritingOutputToFile();
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            const Text("Activate"),
          ],
        ),
        StreamBuilder<String?>(
          stream: player.outputAbsolutePathStream,
          builder: (context, snap) {
            if (snap.data != null) {
              return Column(
                children: [
                  Text(
                    snap.data!,
                    style: TextStyle(
                      fontFamily: Platform.isIOS ? "Courier" : "monospace",
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: snap.data!));
                      },
                      child: const Text("Copy to clipboard"))
                ],
              );
            }

            return const Text("No output file path");
          },
        )
      ],
    );
  }
}
