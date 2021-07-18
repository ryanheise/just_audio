# just_audio

just_audio is a feature-rich audio player for Android, iOS, macOS and web.

![Screenshot with arrows pointing to features](https://user-images.githubusercontent.com/19899190/125459608-e89cd6d4-9f09-426c-abcc-ed7513d9acfc.png)

### Mixing and matching audio plugins

The flutter plugin ecosystem contains a wide variety of useful audio plugins. In order to allow these to work together in a single app, just_audio "just" plays audio. By focusing on a single responsibility, different audio plugins can safely work together without overlapping responsibilities causing runtime conflicts.

Other common audio capabilities are optionally provided by separate plugins:

* [just_audio_background](https://pub.dev/packages/just_audio_background): Use this to allow your app to play audio in the background and respond to controls on the lockscreen, media notification, headset, AndroidAuto/CarPlay or smart watch.
* [audio_service](https://pub.dev/packages/audio_service): Use this if your app has more advanced background audio requirements than can be supported by `just_audio_background`.
* [audio_session](https://pub.dev/packages/audio_session): Use this to configure and manage how your app interacts with other audio apps (e.g. phone call or navigator interruptions).

## Vote on upcoming features

Press the thumbs up icon on the GitHub issues you would like to vote on:

* Pitch shifting: [#329](https://github.com/ryanheise/just_audio/issues/329)
* Equaliser: [#147](https://github.com/ryanheise/just_audio/issues/147)
* Casting support (Chromecast and AirPlay): [#211](https://github.com/ryanheise/just_audio/issues/211)
* Volume boost and skip silence: [#307](https://github.com/ryanheise/just_audio/issues/307)
* [All feature requests sorted by popularity](https://github.com/ryanheise/just_audio/issues?q=is%3Aopen+is%3Aissue+label%3Aenhancement+sort%3Areactions-%2B1-desc)

Please also consider pressing the thumbs up button at the top of [this page](https://pub.dev/packages/just_audio) (pub.dev) if you would like to bring more momentum to the project. More users leads to more bug reports and feature requests, which leads to increased stability and functionality.

## Credits

This project is supported by the amazing open source community of GitHub contributors and sponsors. Thank you!

## Features

| Feature                        | Android   | iOS     | macOS   | Web     |
| -------                        | :-------: | :-----: | :-----: | :-----: |
| read from URL                  | ✅        | ✅      | ✅      | ✅      |
| read from file                 | ✅        | ✅      | ✅      | ✅      |
| read from asset                | ✅        | ✅      | ✅      | ✅      |
| read from byte stream          | ✅        | ✅      | ✅      | ✅      |
| request headers                | ✅        | ✅      | ✅      |         |
| DASH                           | ✅        |         |         |         |
| HLS                            | ✅        | ✅      | ✅      |         |
| ICY metadata                   | ✅        | ✅      | ✅      |         |
| buffer status/position         | ✅        | ✅      | ✅      | ✅      |
| play/pause/seek                | ✅        | ✅      | ✅      | ✅      |
| set volume/speed               | ✅        | ✅      | ✅      | ✅      |
| clip audio                     | ✅        | ✅      | ✅      | ✅      |
| playlists                      | ✅        | ✅      | ✅      | ✅      |
| looping/shuffling              | ✅        | ✅      | ✅      | ✅      |
| compose audio                  | ✅        | ✅      | ✅      | ✅      |
| gapless playback               | ✅        | ✅      | ✅      |         |
| report player errors           | ✅        | ✅      | ✅      | ✅      |
| handle phonecall interruptions | ✅        | ✅      |         |         |
| buffering/loading options      | ✅        | ✅      | ✅      |         |
| set pitch                      | ✅        |         |         |         |
| skip silence                   | ✅        |         |         |         |
| equalizer                      | ✅        |         |         |         |
| volume boost                   | ✅        |         |         |         |

## Experimental features

| Feature                                                                            | Android   | iOS     | macOS   | Web     |
| -------                                                                            | :-------: | :-----: | :-----: | :-----: |
| Simultaneous downloading+caching                                                   | ✅        | ✅      | ✅      |         |
| Waveform visualizer (See [#97](https://github.com/ryanheise/just_audio/issues/97)) | ✅        | ✅      |         |         |
| FFT visualizer (See [#97](https://github.com/ryanheise/just_audio/issues/97))      | ✅        |         |         |         |
| Background                                                                         | ✅        | ✅      | ✅      | ✅      |

Please consider reporting any bugs you encounter [here](https://github.com/ryanheise/just_audio/issues) or submitting pull requests [here](https://github.com/ryanheise/just_audio/pulls).

## Migrating from 0.5.x to 0.6.x

`load()` and `stop()` have new behaviours in 0.6.x documented [here](https://pub.dev/documentation/just_audio/latest/just_audio/AudioPlayer-class.html) that provide greater flexibility in how system resources are acquired and released. For a quick migration that maintains 0.5.x behaviour:

* Replace `await player.load(source);` by `await player.setAudioSource(source);`
* Replace `await stop();` by `await player.pause(); await player.seek(Duration.zero);`

## Tutorials

* [Create a simple Flutter music player app](https://ishouldgotosleep.com/simple-flutter-music-player-app/) by @mvolpato
* [Playing short audio clips in Flutter with Just Audio](https://suragch.medium.com/playing-short-audio-clips-in-flutter-with-just-audio-3c80eb7eb6ea?sk=aaf6cc523c2c6fc747b5087277932607) by @suragch
* [Streaming audio in Flutter with Just Audio](https://suragch.medium.com/steaming-audio-in-flutter-with-just-audio-7435fcf672bf?sk=c7163e8496b914c9e0e5446ec6020f04) by @suragch
* [Managing playlists in Flutter with Just Audio](https://suragch.medium.com/managing-playlists-in-flutter-with-just-audio-c4b8f2af12eb?sk=1b1ffa2cb0b3ed50a320d8cc32cef342) by @suragch

## Example

Initialisation:

```dart
final player = AudioPlayer();
var duration = await player.setUrl('https://foo.com/bar.mp3');
var duration = await player.setFilePath('/path/to/file.mp3');
var duration = await player.setAsset('path/to/asset.mp3');
```

Setting the HTTP user agent:

```dart
final player = AudioPlayer(
  userAgent: 'myradioapp/1.0 (Linux;Android 11) https://myradioapp.com',
);
```

Headers:

```dart
var duration = await player.setUrl('https://foo.com/bar.mp3',
    headers: {'header1': 'value1', 'header2': 'value2'});
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
await player.setAudioSource(
  ConcatenatingAudioSource(
    // Start loading next item just before reaching it.
    useLazyPreparation: true, // default
    // Customise the shuffle algorithm.
    shuffleOrder: DefaultShuffleOrder(), // default
    // Specify the items in the playlist.
    children: [
      AudioSource.uri(Uri.parse("https://example.com/track1.mp3")),
      AudioSource.uri(Uri.parse("https://example.com/track2.mp3")),
      AudioSource.uri(Uri.parse("https://example.com/track3.mp3")),
    ],
  ),
  // Playback will be prepared to start from track1.mp3
  initialIndex: 0, // default
  // Playback will be prepared to start from position zero.
  initialPosition: Duration.zero, // default
);
await player.seekToNext();
await player.seekToPrevious();
// Jump to the beginning of track3.mp3.
await player.seek(Duration(milliseconds: 0), index: 2);
```

Looping and shuffling:

```dart
await player.setLoopMode(LoopMode.off); // no looping (default)
await player.setLoopMode(LoopMode.all); // loop playlist
await player.setLoopMode(LoopMode.one); // loop current item
await player.setShuffleModeEnabled(true); // shuffle playlist
```

Composing audio sources:

```dart
player.setAudioSource(
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

Managing resources:

```dart
// Set the audio source but manually load audio at a later point.
await player.setUrl('https://a.b/c.mp3', preload: false);
// Acquire platform decoders and start loading audio.
var duration = await player.load();
// Unload audio and release decoders until needed again.
await player.stop();
// Permanently release decoders/resources used by the player.
await player.dispose();
```

Catching player errors: 

```dart
try {
  await player.setUrl("https://s3.amazonaws.com/404-file.mp3");
} on PlayerException catch (e) {
  // iOS/macOS: maps to NSError.code
  // Android: maps to ExoPlayerException.type
  // Web: maps to MediaError.code
  print("Error code: ${e.code}");
  // iOS/macOS: maps to NSError.localizedDescription
  // Android: maps to ExoPlaybackException.getMessage()
  // Web: a generic message
  print("Error message: ${e.message}");
} on PlayerInterruptedException catch (e) {
  // This call was interrupted since another audio source was loaded or the
  // player was stopped or disposed before this audio source could complete
  // loading.
  print("Connection aborted: ${e.message}");
} catch (e) {
  // Fallback for all errors
  print(e);
}
```

Listening to state changes:

```dart
player.playerStateStream.listen((state) {
  if (state.playing) ... else ...
  switch (state.processingState) {
    case ProcessingState.idle: ...
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

## The state model

The state of the player consists of two orthogonal states: `playing` and `processingState`. The `playing` state typically maps to the app's play/pause button and only ever changes in response to direct method calls by the app. By contrast, `processingState` reflects the state of the underlying audio decoder and can change both in response to method calls by the app and also in response to events occurring asynchronously within the audio processing pipeline. The following diagram depicts the valid state transitions:

![just_audio_states](https://user-images.githubusercontent.com/19899190/103147563-e6601100-47aa-11eb-8baf-dee00d8e2cd4.png)

This state model provides a flexible way to capture different combinations of states such as playing+buffering vs paused+buffering, and this allows state to be more accurately represented in an app's UI. It is important to understand that even when `playing == true`, no sound will actually be audible unless `processingState == ready` which indicates that the buffers are filled and ready to play. This makes intuitive sense when imagining the `playing` state as mapping onto an app's play/pause button:

* When the user presses "play" to start a new track, the button will immediately reflect the "playing" state change although there will be a few moments of silence while the audio is loading (while `processingState == loading`) but once the buffers are finally filled (i.e. `processingState == ready`), audio playback will begin.
* When buffering occurs during playback (e.g. due to a slow network connection), the app's play/pause button remains in the `playing` state, although temporarily no sound will be audible while `processingState == buffering`. Sound will be audible again as soon as the buffers are filled again and `processingState == ready`.
* When playback reaches the end of the audio stream, the player remains in the `playing` state with the seek bar positioned at the end of the track. No sound will be audible until the app seeks to an earlier point in the stream. Some apps may choose to display a "replay" button in place of the play/pause button at this point, which calls `seek(Duration.zero)`. When clicked, playback will automatically continue from the seek point (because it was never paused in the first place). Other apps may instead wish to listen for the `processingState == completed` event and programmatically pause and rewind the audio at that point.

Apps that wish to react to both orthogonal states through a single combined stream may listen to `playerStateStream`. This stream will emit events that contain the latest value of both `playing` and `processingState`.

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

To allow your application to access audio files on the Internet, add the following permission to your `AndroidManifest.xml` file:

```xml
    <uses-permission android:name="android.permission.INTERNET"/>
```

If you wish to connect to non-HTTPS URLS, also add the following attribute to the `application` element:

```xml
    <application ... android:usesCleartextTraffic="true">
```

If you need access to the player's AudioSession ID, you can listen to `AudioPlayer.androidAudioSessionIdStream`. Note that the AudioSession ID will change whenever you set new AudioAttributes.

### iOS

Using the default configuration, the App Store will detect that your app uses the AVAudioSession API which includes a microphone API, and for privacy reasons it will ask you to describe your app's usage of the microphone. If your app does indeed use the microphone, you can describe your usage by editing the `Info.plist` file as follows:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>... explain why the app uses the microphone here ...</string>
```

But if your app does not use the microphone, you can pass a build option to "compile out" any microphone code so that the App Store won't ask for the above usage description. To do so, edit your `ios/Podfile` as follows:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    
    # ADD THE NEXT SECTION
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'AUDIO_SESSION_MICROPHONE=0'
      ]
    end
    
  end
end
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

The iOS player relies on server headers (e.g. `Content-Type`, `Content-Length` and [byte range requests](https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariWebContent/CreatingVideoforSafarioniPhone/CreatingVideoforSafarioniPhone.html#//apple_ref/doc/uid/TP40006514-SW6)) to know how to decode the file and where applicable to report its duration. In the case of files, iOS relies on the file extension.

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

The macOS player relies on server headers (e.g. `Content-Type`, `Content-Length` and [byte range requests](https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariWebContent/CreatingVideoforSafarioniPhone/CreatingVideoforSafarioniPhone.html#//apple_ref/doc/uid/TP40006514-SW6)) to know how to decode the file and where applicable to report its duration. In the case of files, macOS relies on the file extension.

## Related plugins

* [audio_service](https://pub.dev/packages/audio_service): play any audio in the background and control playback from the lock screen, Android notifications, the iOS Control Center, and headset buttons.
* [audio_session](https://pub.dev/packages/audio_session): configure your app's audio category (e.g. music vs speech) and configure how your app interacts with other audio apps (e.g. audio focus, ducking, mixing).
