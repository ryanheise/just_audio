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
