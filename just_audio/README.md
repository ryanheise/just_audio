# just_audio

This Flutter plugin plays audio from URLs, files, assets, DASH/HLS streams and playlists. Furthermore, it can clip, concatenate, loop, shuffle and compose audio into complex arrangements with gapless playback. This plugin can be used with [audio_service](https://pub.dev/packages/audio_service) to play audio in the background and control playback from the lock screen, Android notifications, the iOS Control Center, and headset buttons.

## Features

| Feature                        | Android   | iOS     | macOS   | Web     |
| -------                        | :-------: | :-----: | :-----: | :-----: |
| read from URL                  | ✅        | ✅      | ✅      | ✅      |
| read from file                 | ✅        | ✅      | ✅      |         |
| read from asset                | ✅        | ✅      | ✅      |         |
| request headers                | ✅        | ✅      | ✅      |         |
| DASH                           | ✅        |         |         |         |
| HLS                            | ✅        | ✅      | ✅      |         |
| buffer status/position         | ✅        | ✅      | ✅      | ✅      |
| play/pause/seek                | ✅        | ✅      | ✅      | ✅      |
| set volume                     | ✅        | ✅      | ✅      | ✅      |
| set speed                      | ✅        | ✅      | ✅      | ✅      |
| clip audio                     | ✅        | ✅      | ✅      | ✅      |
| playlists                      | ✅        | ✅      | ✅      | ✅      |
| looping                        | ✅        | ✅      | ✅      | ✅      |
| shuffle                        | ✅        | ✅      | ✅      | ✅      |
| compose audio                  | ✅        | ✅      | ✅      | ✅      |
| gapless playback               | ✅        | ✅      | ✅      |         |
| report player errors           | ✅        | ✅      | ✅      | ✅      |
| Handle phonecall interruptions | ✅        | ✅      |         |         |

Please consider reporting any bugs you encounter [here](https://github.com/ryanheise/just_audio/issues) or submitting pull requests [here](https://github.com/ryanheise/just_audio/pulls).

## Example

![just_audio](https://user-images.githubusercontent.com/19899190/89558581-bf369080-d857-11ea-9376-3a5055284bab.png)

Initialisation:

```dart
final player = AudioPlayer();
var duration = await player.setUrl('https://foo.com/bar.mp3');
var duration = await player.setFilePath('/path/to/file.mp3');
var duration = await player.setAsset('path/to/asset.mp3');
```

Standard controls:

```dart
player.play(); // Usually you don't want to wait for playback to finish.
await player.seek(Duration(seconds: 10));
await player.pause();
```

Clipping audio:

```dart
await player.setClip(start: Duration(seconds: 10), end: Duration(seconds: 20));
await player.play(); // Waits until the clip has finished playing
```
Adjusting audio:

```dart
await player.setSpeed(2.0); // Double speed
await player.setVolume(0.5); // Halve volume
```

Gapless playlists:

```dart
await player.load(
  ConcatenatingAudioSource(
    children: [
      AudioSource.uri(Uri.parse("https://example.com/track1.mp3")),
      AudioSource.uri(Uri.parse("https://example.com/track2.mp3")),
      AudioSource.uri(Uri.parse("https://example.com/track3.mp3")),
    ],
  ),
);
player.seekToNext();
player.seekToPrevious();
// Jump to the beginning of track3.mp3.
player.seek(Duration(milliseconds: 0), index: 2);
```

Looping and shuffling:

```dart
player.setLoopMode(LoopMode.off); // no looping (default)
player.setLoopMode(LoopMode.all); // loop playlist
player.setLoopMode(LoopMode.one); // loop current item
player.setShuffleModeEnabled(true); // shuffle except for current item
```

Composing audio sources:

```dart
player.load(
  // Loop child 4 times
  LoopingAudioSource(
    count: 4,
    // Play children one after the other
    child: ConcatenatingAudioSource(
      children: [
        // Play a regular media file
        ProgressiveAudioSource(Uri.parse("https://example.com/foo.mp3")),
        // Play a DASH stream
        DashAudioSource(Uri.parse("https://example.com/audio.mdp")),
        // Play an HLS stream
        HlsAudioSource(Uri.parse("https://example.com/audio.m3u8")),
        // Play a segment of the child
        ClippingAudioSource(
          child: ProgressiveAudioSource(Uri.parse("https://w.xyz/p.mp3")),
          start: Duration(seconds: 25),
          end: Duration(seconds: 30),
        ),
      ],
    ),
  ),
);
```

Releasing resources:

```dart
await player.dispose();
```

Catching player errors: 

```dart
try {
  await player.setUrl("https://s3.amazonaws.com/404-file.mp3");
} catch (e) {
  print("Error: $e");
}
```

Listening to state changes:

```dart
player.playerStateStream.listen((state) {
  if (state.playing) ...  else ...
  switch (state.processingState) {
    case ProcessingState.none: ...
    case ProcessingState.loading: ...
    case ProcessingState.buffering: ...
    case ProcessingState.ready: ...
    case ProcessingState.completed: ...
  }
});

// See also:
// - durationStream
// - positionStream
// - bufferedPositionStream
// - sequenceStateStream
// - sequenceStream
// - currentIndexStream
// - icyMetadataStream
// - playingStream
// - processingStateStream
// - loopModeStream
// - shuffleModeEnabledStream
// - volumeStream
// - speedStream
// - playbackEventStream
```

## Configuring the audio session

If your app uses audio, you should tell the operating system what kind of usage scenario your app has and how your app will interact with other audio apps on the device. Different audio apps often have unique requirements. For example, when a navigator app speaks driving instructions, a music player should duck its audio while a podcast player should pause its audio. Depending on which one of these three apps you are building, you will need to configure your app's audio settings and callbacks to appropriately handle these interactions.

just_audio will by default choose settings that are appropriate for a music player app which means that it will automatically duck audio when a navigator starts speaking, but should pause when a phone call or another music player starts. If you are building a podcast player or audio book reader, this behaviour would not be appropriate. While the user may be able to comprehend the navigator instructions while ducked music is playing in the background, it would be much more difficult to understand the navigator instructions while simultaneously listening to an audio book or podcast.

You can use the [audio_session](https://pub.dev/packages/audio_session) package to change the default audio session configuration for your app. E.g. for a podcast player, you may use:

```dart
final session = await AudioSession.instance;
await session.configure(AudioSessionConfiguration.speech());
```

Note: If your app uses a number of different audio plugins, e.g. for audio recording, or text to speech, or background audio, it is possible that those plugins may internally override each other's audio session settings, so it is recommended that you apply your own preferred configuration using audio_session after all other audio plugins have loaded. You may consider asking the developer of each audio plugin you use to provide an option to not overwrite these global settings and allow them be managed externally.

## Platform specific configuration

### Android

If you wish to connect to non-HTTPS URLS, add the following attribute to the `application` element of your `AndroidManifest.xml` file:

```xml
    <application ... android:usesCleartextTraffic="true">
```

If you need access to the player's AudioSession ID, you can listen to `AudioPlayer.androidAudioSessionIdStream`. Note that the AudioSession ID will change whenever you set new AudioAttributes.

### iOS

Regardless of whether your app uses the microphone, Apple will require you to add the following key to your `Info.plist` file. The message will simply be ignored if your app doesn't use the microphone:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>... explain why you use (or don't use) the microphone ...</string>
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

### macOS

To allow your macOS application to access audio files on the Internet, add the following to your `DebugProfile.entitlements` and `Release.entitlements` files:

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

## Related plugins

* [audio_service](https://pub.dev/packages/audio_service): play any audio in the background and control playback from the lock screen, Android notifications, the iOS Control Center, and headset buttons.
* [audio_session](https://pub.dev/packages/audio_session): configure your app's audio category (e.g. music vs speech) and configure how your app interacts with other audio apps (e.g. audio focus, ducking, mixing).
