# just_audio

A Flutter plugin to play audio from URLs, files, assets and DASH/HLS streams. This plugin can be used with [audio_service](https://pub.dev/packages/audio_service) to play audio in the background and control playback from the lock screen, Android notifications, the iOS Control Center, and headset buttons.

## Features

| Feature              | Android   | iOS        | Web        |
| -------              | :-------: | :-----:    | :-----:    |
| read from URL        | ✅        | ✅         | ✅         |
| read from file       | ✅        | ✅         |            |
| read from asset      | ✅        | ✅         |            |
| DASH                 | ✅        | (untested) | (untested) |
| HLS                  | ✅        | (untested) | (untested) |
| play/pause/stop/seek | ✅        | ✅         | ✅         |
| set volume           | ✅        | (untested) | (untested) |
| set speed            | ✅        | (untested) | (untested) |
| custom actions       | ✅        | (untested) | (untested) |
| clip audio           | ✅        |            | ✅         |
| dispose              | ✅        | ✅         | ✅         |

This plugin has been tested on Android and Web, and is being made available for testing on iOS. Please consider reporting any bugs you encounter [here](https://github.com/ryanheise/just_audio/issues) or submitting pull requests [here](https://github.com/ryanheise/just_audio/pulls).

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

## Connecting to HTTP URLS

If you wish to connect to HTTP URLS, some additional platform-specific configuration is required.

### iOS

Add the following to your `Info.plist` file:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
    <key>NSAllowsArbitraryLoadsForMedia</key>
    <true/>
</dict>
```

### Android

Add the following attribute to the `application` element of your `AndroidManifest.xml` file:

```xml
    <application ... android:usesCleartextTraffic="true">
```

## Todo

* FLAC support
* Gapless playback
