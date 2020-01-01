# just_audio

A Flutter plugin to play audio from URLs, files, assets and DASH/HLS streams. This plugin can be used with [audio_service](https://pub.dev/packages/audio_service) to play audio in the background and control playback from the lock screen, Android notifications, the iOS Control Center, and headset buttons.

## Features

| Feature              | Android   | iOS        |
| -------              | :-------: | :-----:    |
| read from URL        | ✅        | ✅         |
| read from file       | ✅        | (untested) |
| read from asset      | ✅        | (untested) |
| DASH                 | ✅        | (untested) |
| HLS                  | ✅        | (untested) |
| play/pause/stop/seek | ✅        | ✅         |
| set volume           | ✅        | (untested) |
| set speed            | ✅        | (untested) |
| custom actions       | ✅        | (untested) |
| clip audio           | ✅        |            |
| dispose              | ✅        | ✅         |

This plugin has been tested on Android, and is being made available for testing on iOS. Please consider reporting any bugs you encounter [here](https://github.com/ryanheise/just_audio/issues) or submitting pull requests [here](https://github.com/ryanheise/just_audio/pulls).

## Example

Initialisation:

```dart
final player = AudioPlayer();
var duration = await player.setUrl('https://foo.com/bar.mp3');
```

Standard controls:

```dart
player.play();
await player.seek(Duration(seconds: 10));
await player.pause();
await player.stop();
```

Clipping audio:

```dart
await player.setClip(start: Duration(seconds: 10), end: Duration(seconds: 20));
await player.play(); // Waits for playback to finish
```

Release resources:

```dart
await player.dispose();
```

## Todo

* FLAC support
* Web support
* Gapless playback
