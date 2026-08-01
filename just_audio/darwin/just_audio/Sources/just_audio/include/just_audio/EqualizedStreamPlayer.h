#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

/// Streams a live HTTP audio source through an AVAudioEngine graph with a
/// 10-band AVAudioUnitEQ. Proven-recipe pipeline:
///   URLSession → AudioFileStream (parse) → AudioConverter (decode → Float32)
///   → AVAudioPlayerNode → AVAudioUnitEQ → mainMixer → output.
///
/// Band centres: 31.25, 62.5, 125, 250, 500, 1k, 2k, 4k, 8k, 16 kHz.
///
/// `captureFile` (optional, .caf/.wav path): if set, the post-EQ PCM is also
/// written to disk for offline verification (spectrum/level inspection) — this
/// is how the harness proves the EQ is audible without relying on ears.
@interface EqualizedStreamPlayer : NSObject

- (void)playURL:(NSURL *)url;
- (void)stop;
/// 10 dB values (clamped ±12). nil/empty/flat → all bands 0 dB (pass-through).
- (void)setGains:(nullable NSArray<NSNumber *> *)gains;
/// Mute test: when YES, the scheduled PCM is zeroed (proves the tap owns output).
- (void)setMute:(BOOL)mute;

@property (nonatomic, readonly, getter=isPlaying) BOOL playing;
/// Linear playback volume (0.0–1.0) applied to the EQ'd renderer node.
@property (nonatomic) float volume;
/// Path of a file to also write post-EQ PCM to (set before playURL:).
@property (nonatomic, copy, nullable) NSString *captureFile;

@end
