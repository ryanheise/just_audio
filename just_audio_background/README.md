# just_audio_background

This experimental package adds background playback and media notification support to [`just_audio`][1].

Just add this dependency alongside just_audio, and then in your app's startup logic, call:

```dart
JustAudioBackground.init();
```

Create your player as normal:

```dart
player = AudioPlayer();
```

But before setting an audio source, check to see if the player is already running in the background:

```dart
if (await JustAudioBackground.running) {
  // If the player is already running in the background, load its state into
  // the current isolate.
  await player.load();
} else {
  // If nothing is already running, initialise the player.
  await player.setAudioSource(...);
}
```

Caveats:

* Headers, caching, byte streams, and the HTTP proxy, are not supported. This may be addressed in a future version.
* Hot reloading does not work. This may be addressed in a future version.

[1]: ../just_audio
