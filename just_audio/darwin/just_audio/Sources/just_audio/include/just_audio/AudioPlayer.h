#import <AVFoundation/AVFoundation.h>
#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#else
#import <Flutter/Flutter.h>
#endif

@interface AudioPlayer : NSObject<AVPlayerItemMetadataOutputPushDelegate>

@property (readonly, nonatomic) AVQueuePlayer *player;
@property (readonly, nonatomic) float speed;

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar playerId:(NSString*)idParam loadConfiguration:(NSDictionary *)loadConfiguration useLazyPreparation:(BOOL)useLazyPreparation;
- (void)dispose:(BOOL)calledFromDealloc;
/// Push the 10-band gain vector (dB) to the AVAudioEngine equaliser
/// (EqualizedStreamPlayer), the sole renderer for live http(s) streams.
/// Always-on: nil/empty/0 dB is flat pass-through; non-flat values update
/// the AVAudioUnitEQ bands live (no arm/disarm, no engine swap). Driven by
/// the top-level `setEqualizerGains` plugin method.
- (void)setEqualizerGains:(NSArray *)gains;

@end

enum ProcessingState {
    psIdle,
    psLoading,
    psBuffering,
    psReady,
    psCompleted
};

enum LoopMode {
    lmLoopOff,
    lmLoopOne,
    lmLoopAll
};
