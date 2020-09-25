#import <Flutter/Flutter.h>

@interface AudioPlayer : NSObject<FlutterStreamHandler>

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar playerId:(NSString*)idParam configuredSession:(BOOL)configuredSession;

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
