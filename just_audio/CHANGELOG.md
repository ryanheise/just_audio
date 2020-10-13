## 0.5.4+1

* Add web dependency.

## 0.5.4

* Use audio_session 0.0.9.

## 0.5.3

* ARC fixes on iOS.
* Update to use platform interface 1.1.0.
* Retain player.position after dispose.
* Fix unnattached player bug in ConcatenatingAudioSource (@nuc134r).

## 0.5.2

* Fix bug in concatenating add/addAll.

## 0.5.1

* Fix bug in loading from assets.
* Ignore method calls from invalid states.
* Forward exceptions from iOS platform implementation.

## 0.5.0

* Convert to federated plugin.

## 0.4.5

* Fix iOS bug in seek/position/duration in HLS streams (@snaeji).
* Fix web bug for audio sources with unknown durations.

## 0.4.4

* Fix crash when disposing of positionStream controller.
* Handle interruptions correctly when willPauseWhenDucked is set.
* Correct seek/position/duration in HLS streams (@snaeji).
* Resume at correct speed after seek on iOS (@subhash279).

## 0.4.3

* Add section to README on configuring the audio session.

## 0.4.2

* Make default audio session settings compatible with iOS control center.
* Update README to mention NSMicrophoneUsageDescription key in Info.plist.

## 0.4.1

* Fix setSpeed bug on iOS.

## 0.4.0

* Handles audio focus/interruptions via audio_session
* Bug fixes

## 0.3.4

* Fix bug in icy metadata
* Allow Android AudioAttributes to be set
* Provide access to Android audio session ID

## 0.3.3

* Remove dependency on Java streams API

## 0.3.2

* Fix dynamic methods on ConcatenatingAudioSource for iOS/Android
* Add sequenceStream/sequenceStateStream
* Change asset URI from asset:// to asset:///

## 0.3.1

* Prevent hang in dispose

## 0.3.0

* Playlists
* Looping
* Shuffling
* Composing
* Clipping support added for iOS/macOS
* New player state model consisting of:
  * playing: true/false
  * processingState: none/loading/buffering/ready/completed
* Feature complete on iOS and macOS (except for DASH)
* Improved example
* Exception classes

## 0.2.2

* Fix dependencies for stable channel.

## 0.2.1

* Improve handling of headers.
* Report setUrl errors and duration on web.

## 0.2.0

* Support dynamic duration
* Support seeking to end of live streams
* Support request headers
* V2 implementation
* Report setUrl errors on iOS
* setUrl throws exception if interrupted
* Return null when duration is unknown

## 0.1.10

* Option to set audio session category on iOS.

## 0.1.9

* Bug fixes.

## 0.1.8

* Reduce distortion at slow speeds on iOS

## 0.1.7

* Minor bug fixes.

## 0.1.6

* Eliminate event lag over method channels.
* Report setUrl errors on Android.
* Report Icy Metadata on Android.
* Bug fixes.

## 0.1.5

* Update dependencies and documentation.

## 0.1.4

* Add MacOS implementation.
* Support cross-platform redirects on Android.
* Bug fixes.

## 0.1.3

* Fix bug in web implementation.

## 0.1.2

* Broadcast how much audio has been buffered.

## 0.1.1

* Web implementation.
* iOS option to minimize stalling.
* Fix setAsset on iOS.

## 0.1.0

* Separate buffering state from PlaybackState.
* More permissive state transitions.
* Support playing local files on iOS.

## 0.0.6

* Bug fixes.

## 0.0.5

* API change for audio clipping.
* Performance improvements and bug fixes on Android.

## 0.0.4

* Remove reseeking hack.

## 0.0.3

* Feature to change audio speed.

## 0.0.2

* iOS implementation for testing (may not work).

## 0.0.1

* Initial release with Android implementation.
