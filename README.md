# audio_player

A new Flutter audio player plugin designed to support background playback with [audio_service](https://pub.dev/packages/audio_service)

## Features

* Plays audio from streams, files and assets.
* Broadcasts state changes helpful in streaming apps such as `buffering` and `connecting` in addition to the typical `playing`, `paused` and `stopped` states.
* Control audio playback via standard operations: play, pause, stop, setVolume, seek.
* Compatible with [audio_service](https://pub.dev/packages/audio_service) to support full background playback, queue management, and controlling playback from the lock screen, notifications and headset buttons.

The initial release is for Android. iOS is the next priority.
