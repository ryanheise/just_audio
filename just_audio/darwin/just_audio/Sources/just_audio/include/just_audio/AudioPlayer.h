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
/// Tell the EQ renderer to fetch this ORIGINAL upstream stream URL directly
/// (instead of the proxy URL AVQueuePlayer loads), so EqualizedStreamPlayer is
/// an independent consumer and doesn't contend with AVQueuePlayer for the
/// proxy. Set per stream by the app; cleared on each load. nil disables EQ
/// routing (falls back to normal AVQueuePlayer playback).
- (void)setEqualizerStreamUrl:(NSString *)url;

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
