#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

/// 10-band graphic equaliser for the darwin (AVPlayer) backend.
///
/// Installs an `MTAudioProcessingTap` on each `AVPlayerItem`'s audio tracks
/// (via `AVMutableAudioMix`) and applies a cascaded peaking-EQ biquad chain
/// in the tap's PCM process callback. AVPlayer stays the streaming engine —
/// the tap only intercepts *decoded* PCM — so HLS/ICY streaming, background
/// audio, AirPlay and the `audio_service` integration are untouched. This is
/// the Phase B path for iOS + macOS (EQUALISER_PLAN.md §3).
///
/// Gains are applied **live**: a slider drag updates the stored vector under a
/// lock and the next process callback recomputes coefficients — there is no
/// player recreation (unlike the desktop libmpv `af` path). A flat (all-zero)
/// vector disarms the engine: existing taps bypass, and new player items
/// install no tap at all.
///
/// Lifecycle (§6): the tap is (re)installed on every item that reaches
/// `AVPlayerItemStatusReadyToPlay` (audio tracks are only reliably available
/// then). Station changes create a new `AVPlayerItem`, so the tap re-installs
/// automatically. The gain vector is held on the `AudioPlayer` (one EQ per
/// player), shared across that player's items.
@interface EqualizerEngine : NSObject

/// Set the 10-band gain vector in dB (clamped to ±12). `nil`, an empty array,
/// or an all-flat vector disarms the engine.
- (void)setGains:(nullable NSArray<NSNumber *> *)gains;

/// Whether a non-flat curve is currently armed (taps should install/process).
@property (readonly, nonatomic) BOOL armed;

/// Install a tap on the item's audio tracks if armed. Called when the item
/// reaches `AVPlayerItemStatusReadyToPlay` (tracks then available). Falls back
/// to an async asset-track load if `item.tracks` is empty (the HLS case).
/// Safe to call repeatedly; installs at most one tap set per call.
- (void)attachToPlayerItem:(AVPlayerItem *)item;

@end
