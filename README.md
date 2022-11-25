# just_audio_icy
## Audio Player icy metadata behaviour investigation
### 23-Nov-2022 (Mike Relac)
- Added print statements to:
  - `AudioPlayer.java.onMetadata()`
  - `AudioPlayer.java.onTracksChanged()`
- Modified `example_radio.dart` to:
  - handle null/invalid *ArtworkUrl*
  - show *Station*, *StationUrl*, and *ArtworkUrl* above the artwork (if any)
  - append a scrollable list of clickable radio stations below the *play* button. The
station at the head of the list is **radioparadise**. The next station in the list
is **WETF**, the station that illustrates the incorrect metadata `IcyInfo` duplication.
- Prepended console log outputs with 'XXXX' to make for easy filtering.
- Added print statement in `AudioPlayer.java.onTracksChanged()` to verify that the
const value `C.LENGTH_UNSET` is **-1**.


Javadoc tells us that
[`IcyHeaders metadataInterval`](https://exoplayer.dev/doc/reference/com/google/android/exoplayer2/metadata/icy/IcyHeaders.html#metadataInterval)
is _The interval in bytes between metadata chunks (icy-metaint), or C.LENGTH_UNSET if the header was not present._  
*Exactly* which header they are referring to is unknown, as there is clearly a valid, non-null `IcyHeaders` value.

### Handy URLs
[exoplayer Javadoc for `Metadata`](https://exoplayer.dev/doc/reference/com/google/android/exoplayer2/metadata/Metadata.html)  
[exoplayer Javadoc for `IcyHeaders`](https://exoplayer.dev/doc/reference/com/google/android/exoplayer2/metadata/icy/IcyHeaders.html)  
[exoplayer Javadoc for `LENGTH_UNSET`](https://exoplayer.dev/doc/reference/com/google/android/exoplayer2/C.html#LENGTH_UNSET)  
[exoplayer Javadoc for `IcyInfo`](https://exoplayer.dev/doc/reference/com/google/android/exoplayer2/metadata/icy/IcyInfo.html)  

#### *Observations*

Discovered the following when running `example_radio.dart`:
- at program start, radioparadise loads, and the debug console logs:
  - `onTracksChanged()` with correct-looking `IcyMetadata` headers for radioparadise
  - `onMetadata()` with correct-looking `IcyInfo` data for radioparadise
- clicking on **WETF** (drag the listview up first if necessary), the debug console logs:
  - `onTracksChanged()` with correct-looking `IcyMetadata` headers for WETF. But the
  `meteadataInterval` is *-1* (i.e. `C.LENGTH_UNSET`)
  - The print statement in `onMetadata()` *never* shows so thus isn't being called.

#### *Further discussion*
1. It makes sense that `onMetadata()` should always be called if there is a non-null `IcyHeaders`
instance, regardless of the `IcyHeaders.metadataInterval` value.  
Alternatively, it could be
argued that if `IcyHeaders.metadataInterval` is `C.LENGTH_UNSET`, it _shouldn't_ be called.
However, that seems incorrect, as there _is_ a header.
1. Since **WETF** has a non-null `IcyHeaders` value (and it appears to contain **WETF** header
info), it makes sense that `broadcastImmediatePlaybackEvent()` is called.
1. Why, then, isn't `onMetadata()` being called for **WETF**?

### 25-Nov-2022 (Mike Relac) - Proposed solution
Since a valid header with a `metadataInterval` value of `C.LENGTH_UNSET` doesn't
generate a call to `onMetadata()`, in `onTracksChanged()` simply set the `icyInfo`
 instance variable to null to clear the stale data
https://github.com/ryanheise/just_audio/blob/9526090986af4fd9f193862052c317fd8faa67da/just_audio/android/src/main/java/com/ryanheise/just_audio/AudioPlayer.java#L233-L236
```
                         if (entry instanceof IcyHeaders) {
                            icyHeaders = (IcyHeaders) entry;
                            if (icyHeaders.metadataInterval == C.LENGTH_UNSET) {
                                icyInfo = null;
                            }
                            broadcastImmediatePlaybackEvent();
                        }
```
