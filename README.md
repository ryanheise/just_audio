# just_audio

This Flutter plugin plays audio from URLs, files, assets, DASH/HLS streams and playlists. Furthermore, it can clip, concatenate, loop, shuffle and compose audio into complex arrangements with gapless playback. This plugin can be used with [audio_service](https://pub.dev/packages/audio_service) to play audio in the background and control playback from the lock screen, Android notifications, the iOS Control Center, and headset buttons.

## Features

| Feature                | Android   | iOS     | MacOS   | Web     |
| -------                | :-------: | :-----: | :-----: | :-----: |
| read from URL          | ✅        | ✅      | ✅      | ✅      |
| read from file         | ✅        | ✅      | ✅      |         |
| read from asset        | ✅        | ✅      | ✅      |         |
| request headers        | ✅        | ✅      | ✅      |         |
| DASH                   | ✅        |         |         |         |
| HLS                    | ✅        | ✅      | ✅      |         |
| buffer status/position | ✅        | ✅      | ✅      | ✅      |
| play/pause/seek        | ✅        | ✅      | ✅      | ✅      |
| set volume             | ✅        | ✅      | ✅      | ✅      |
| set speed              | ✅        | ✅      | ✅      | ✅      |
| clip audio             | ✅        | ✅      | ✅      | ✅      |
| playlists              | ✅        | ✅      | ✅      | ✅      |
| looping                | ✅        | ✅      | ✅      | ✅      |
| shuffle                | ✅        | ✅      | ✅      | ✅      |
| compose audio          | ✅        | ✅      | ✅      | ✅      |
| gapless playback       | ✅        | ✅      | ✅      |         |
| report player errors   | ✅        | ✅      | ✅      | ✅      |

Please consider reporting any bugs you encounter [here](https://github.com/ryanheise/just_audio/issues) or submitting pull requests [here](https://github.com/ryanheise/just_audio/pulls).

## Example

![just_audio](https://user-images.githubusercontent.com/19899190/89558581-bf369080-d857-11ea-9376-3a5055284bab.png)

Initialisation:

```dart
final player = AudioPlayer();
var duration = await player.setUrl('https://foo.com/bar.mp3');
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
    case AudioPlaybackState.none: ...
    case AudioPlaybackState.loading: ...
    case AudioPlaybackState.buffering: ...
    case AudioPlaybackState.ready: ...
    case AudioPlaybackState.completed: ...
  }
});

// See also:
// - durationStream
// - positionStream
// - bufferedPositionStream
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
