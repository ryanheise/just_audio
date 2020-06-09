# just_audio

A Flutter plugin to play audio from URLs, files, assets and DASH/HLS streams. This plugin can be used with [audio_service](https://pub.dev/packages/audio_service) to play audio in the background and control playback from the lock screen, Android notifications, the iOS Control Center, and headset buttons.

## Features

| Feature              | Android   | iOS        | MacOS      | Web        |
| -------              | :-------: | :-----:    | :-----:    | :-----:    |
| read from URL        | ✅        | ✅         | ✅         | ✅         |
| read from file       | ✅        | ✅         | ✅         |            |
| read from asset      | ✅        | ✅         | ✅         |            |
| request headers      | ✅        | ✅         | ✅         |            |
| DASH                 | ✅        | (untested) | (untested) | (untested) |
| HLS                  | ✅        | ✅         | (untested) | (untested) |
| play/pause/stop/seek | ✅        | ✅         | ✅         | ✅         |
| set volume           | ✅        | (untested) | (untested) | ✅         |
| set speed            | ✅        | ✅         | ✅         | ✅         |
| clip audio           | ✅        |            |            | ✅         |
| dispose              | ✅        | ✅         | ✅         | ✅         |
| report player errors | ✅        | ✅         | ✅         | ✅         |

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

Catch player error: 

```dart
player.setUrl("https://s3.amazonaws.com/404-file.mp3").catchError((error) {
  // catch audio error ex: 404 url, wrong url ...
  print(error);
});
```

## Platform specific configuration

### Android

If you wish to connect to non-HTTPS URLS, add the following attribute to the `application` element of your `AndroidManifest.xml` file:

```xml
    <application ... android:usesCleartextTraffic="true">
```

### iOS

If you wish to connect to non-HTTPS URLS, add the following to your `Info.plist` file:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
    <key>NSAllowsArbitraryLoadsForMedia</key>
    <true/>
</dict>
```

By default, iOS will mute your app's audio when your phone is switched to
silent mode. Depending on the requirements of your app, you can change the
default audio session category using `AudioPlayer.setIosCategory`. For example,
if you are writing a media app, Apple recommends that you set the category to
`AVAudioSessionCategoryPlayback`, which you can achieve by adding the following
code to your app's initialisation:

```dart
AudioPlayer.setIosCategory(IosCategory.playback);
```

Note: If your app uses a number of different audio plugins in combination, e.g.
for audio recording, or text to speech, or background audio, it is possible
that those plugins may internally override the setting you choose here. You may
consider asking the developer of each other plugin you use to provide a similar
method so that you can configure the same audio session category universally
across all plugins you use.

### MacOS

To allow your MacOS application to access audio files on the Internet, add the following to your `DebugProfile.entitlements` and `Release.entitlements` files:

```xml
    <key>com.apple.security.network.client</key>
    <true/>
```

If you wish to connect to non-HTTPS URLS, add the following to your `Info.plist` file:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
    <key>NSAllowsArbitraryLoadsForMedia</key>
    <true/>
</dict>
```

## Todo

* Gapless playback
