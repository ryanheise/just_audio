## 4.6.0

* Add androidAudioOffloadPreferences.

## 4.5.0

* Add errorCode/errorMessage to PlaybackEventMessage.
* Add useLazyPreparation to InitRequest for top-level playlist.

## 4.4.0

* Add setWebSinkId for web (@dganzella).

## 4.3.0

* Add setWebCrossOrigin for CORS on web (@danielwinkler).

## 4.2.2

* Add setAllowsExternalPlayback on iOS/macOS.
* Support index-based seeking on Android/iOS/macOS.

## 4.2.1

* Update minimum flutter version to 3.0.

## 4.2.0

- Add InitRequest.androidOffloadSchedulingEnabled.

## 4.1.0

- Add disposeAllPlayers method.

## 4.0.0

- Add playerDataMessageStream.
- Add tag to IndexedAudioSourceMessage.

## 3.1.0

- Add setPitch.
- Add setSkipSilence.
- Add setCanUseNetworkResourcesForLiveStreamingWhilePaused.
- Add setPreferredPeakBitRate.
- Add audioEffectSetEnabled.
- Add androidLoudnessEnhancerSetTargetGain.
- Add androidEqualizerGetParameters.
- Add androidEqualizerBandSetGain.

## 3.0.0

- Null safety.

## 2.0.1

- Fix bug where negative duration is returned instead of null.

## 2.0.0

- Breaking change: Implementations must not set the shuffle order except as
  instructed by setShuffleOrder.
- Breaking change: Implementations must be able to recreate a player instance
  with the same ID as a disposed instance.
- Breaking change: none state renamed to idle.

## 1.1.1

- Add initialPosition and initialIndex to LoadRequest.

## 1.1.0

- Player is now disposed via JustAudioPlatform.disposePlayer().
- AudioPlayerPlatform constructor takes id parameter.

## 1.0.0

- Initial version.
