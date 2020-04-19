#import <Flutter/Flutter.h>

@interface AudioPlayer : NSObject<FlutterStreamHandler>

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar playerId:(NSString*)idParam;

@end

enum PlaybackState {
	none,
	stopped,
	paused,
	playing,
	connecting,
	completed
};
