## 3.0.0-nullsafety.3

- Apply pedantic rules.

## 3.0.0-nullsafety.2

- Merge negative duration bug fix into nullsafety version.

## 3.0.0-nullsafety.1

- Relax SDK version constraints.

## 3.0.0-nullsafety.0

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
