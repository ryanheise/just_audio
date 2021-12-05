#import <FlutterMacOS/FlutterMacOS.h>
#import <AVFoundation/AVFoundation.h>

@interface AudioPlayer : NSObject<AVPlayerItemMetadataOutputPushDelegate>

@property (readonly, nonatomic) AVQueuePlayer *player;
@property (readonly, nonatomic) float speed;
@property (readonly, nonatomic) int visualizerCaptureSize;

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar playerId:(NSString*)idParam loadConfiguration:(NSDictionary *)loadConfiguration;
- (void)dispose;

@end

enum ProcessingState {
	none,
	loading,
	buffering,
	ready,
	completed
};

enum LoopMode {
	loopOff,
	loopOne,
	loopAll
};
