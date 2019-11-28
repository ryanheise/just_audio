# just_audio

A Flutter plugin to play audio from streams, files and assets. This plugin can be used with [audio_service](https://pub.dev/packages/audio_service) to play audio in the background for music players and podcast apps.

## Features

* Plays audio from streams, files and assets.
* Broadcasts state changes helpful in streaming apps such as `buffering` and `connecting` in addition to the typical `playing`, `paused` and `stopped` states.
* Control audio playback via standard operations: play, pause, stop, setVolume, seek.
* Compatible with [audio_service](https://pub.dev/packages/audio_service) to support full background playback, queue management, and controlling playback from the lock screen, notifications and headset buttons.

The initial release is for Android. The next priority is iOS.

## Example

```dart
final player = AudioPlayer();
await player.setUrl('https://foo.com/bar.mp3');
await player.play();
await player.pause();
await player.play(untilPosition: Duration(minutes: 1));
await player.stop()
await player.setUrl('https://foo.com/baz.mp3');
await player.seek(Duration(minutes: 5));
await player.play();
await player.stop();
await player.dispose();
```
