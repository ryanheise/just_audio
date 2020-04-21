#import "JustAudioPlugin.h"
#import "AudioPlayer.h"
#import "AudioPlayer.h"

@implementation JustAudioPlugin {
	NSObject<FlutterPluginRegistrar>* _registrar;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
	FlutterMethodChannel* channel = [FlutterMethodChannel
		methodChannelWithName:@"com.ryanheise.just_audio.methods"
					binaryMessenger:[registrar messenger]];
	JustAudioPlugin* instance = [[JustAudioPlugin alloc] initWithRegistrar:registrar];
	[registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
	self = [super init];
	NSAssert(self, @"super init cannot be nil");
	_registrar = registrar;
	return self;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
	if ([@"init" isEqualToString:call.method]) {
		NSArray* args = (NSArray*)call.arguments;
		NSString* playerId = args[0];
		AudioPlayer* player = [[AudioPlayer alloc] initWithRegistrar:_registrar playerId:playerId];
		result(nil);
	} else {
		result(FlutterMethodNotImplemented);
	}
}

@end
