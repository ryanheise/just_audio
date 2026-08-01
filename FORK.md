# Fork notes — gibbsoft/just_audio

This fork (`fix/content-uri-proxy` branch) tracks upstream
[`ryanheise/just_audio`](https://github.com/ryanheise/just_audio) branch
`minor` and carries **two independent changes** on top of it. They are
unrelated and must not be bundled into a single upstream PR.

## Tracking upstream

- Upstream remote: `upstream` → `ryanheise/just_audio`, default branch `minor`.
- This branch is regularly merged with `upstream/minor` (clean — our changes
  touch darwin sources + one Dart line; upstream's changes are predominantly
  Android/gradle, so there is no file overlap).
- `radiophonia` pins this fork via a git override on `fix/content-uri-proxy`;
  bumping the fork requires re-resolving `pubspec.lock`
  (`flutter pub upgrade just_audio`) and pushing the lock bump.

## (A) Proxy scheme allowlist — the original fork purpose

**What.** `UriAudioSource._onLoad` previously proxied every URI scheme except
`file://`. It now proxies **only `http`/`https`** (tight allowlist), so
`content://`, `asset://` and any other scheme pass through untouched.

**Why.** Android SAF (Storage Access Framework) returns `content://` URIs for
file/directory picks, and those URIs carry permission grants. Routing them
through just_audio's internal HTTP proxy broke playback of user-selected local
media whenever a custom `User-Agent` or headers were configured.

**Status / PR-readiness.** Clean, minimal (one-line gate change), covered by a
regression test. Prepared as a standalone upstream PR on branch
`fix/proxy-content-uri` (based on `upstream/minor`). Per upstream
`CONTRIBUTING.md`, file/link an issue before opening the PR.

## (B) Darwin AVAudioEngine 10-band equalizer (Phase B)

**What.** A live-streaming 10-band graphic EQ for iOS/macOS via
`EqualizedStreamPlayer` (`darwin/just_audio/Sources/just_audio/`):
`URLSession → AudioFileStream → AudioConverter → AVAudioPlayerNode →
AVAudioUnitEQ → mainMixerNode`. Always-on, flat by default; the
`setEqualizerGains` method channel drives the 10 `AVAudioUnitEQ` bands live.
For http(s) sources it is the **sole renderer** — `AVQueuePlayer` stays loaded
for the state machine but is not played; pause cancels the `URLSession` (zero
bytes fetched). Band centres: 31.25, 62.5, 125, 250, 500, 1k, 2k, 4k, 8k,
16 kHz (`canonicalCentresHz` in radiophonia).

**Why.** Upstream has no EQ on darwin (only `AndroidEqualizer`, Android-only —
issue #147). `MTAudioProcessingTap` cannot tap live/HLS streams, so a custom
`AVAudioEngine` decode path is the only viable route.

**Status.** macOS audibly verified in-app; iOS unverified (CI builds green;
`.playback` `AVAudioSession` activation included). The earlier dead
`MTAudioProcessingTap`/`EqualizerEngine` path and the zero-fill diagnostic
have been removed.

**PR-readiness — not yet.** Two blockers:
1. **API shape.** `setEqualizerGains` is a fork-specific API (one-shot 10-band
   array) and does not match upstream's `AndroidEqualizer` (which is
   `AndroidAudioEffect`-flavoured and reports device-defined bands). Do **not**
   retrofit onto `AndroidEqualizer` — its platform-reported band model
   conflicts with a consistent fixed-band graphic EQ (Android devices expose
   ~5 bands). The attractive upstream contribution is a *new* generic
   cross-platform `Equalizer` `AudioEffect` (app declares band centres; each
   platform implements: darwin ✅, media_kit/web ❌, Android could retrofit).
2. **Cross-platform.** Currently darwin-only; media_kit (mpv `af`) and web
   (WebAudio `BiquadFilter`) backends would complete the feature.

Until then this stays fork-local. radiophonia's `EqualizerService` abstraction
+ `resolvePresetGains` interpolation already adapts presets to per-platform
band counts (10 on darwin/desktop, 5 on Android's native EQ).
