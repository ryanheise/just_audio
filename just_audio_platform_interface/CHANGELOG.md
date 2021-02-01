## 3.0.0-nullsafety.0

- Null safety.

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
