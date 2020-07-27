#import <Flutter/Flutter.h>

@interface AudioPlayer : NSObject<FlutterStreamHandler>

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar playerId:(NSString*)idParam configuredSession:(BOOL)configuredSession;

@end

enum PlaybackState {
	none,
	stopped,
	paused,
	playing,
	connecting,
	completed
};

enum LoopMode {
	loopOff,
	loopOne,
	loopAll
};
