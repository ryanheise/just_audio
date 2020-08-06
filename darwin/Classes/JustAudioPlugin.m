#import "JustAudioPlugin.h"
#import "AudioPlayer.h"
#import <AVFoundation/AVFoundation.h>
#include <TargetConditionals.h>

@implementation JustAudioPlugin {
	NSObject<FlutterPluginRegistrar>* _registrar;
	BOOL _configuredSession;
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
		/*AudioPlayer* player =*/ [[AudioPlayer alloc] initWithRegistrar:_registrar playerId:playerId configuredSession:_configuredSession];
		result(nil);
	} else if ([@"setIosCategory" isEqualToString:call.method]) {
#if TARGET_OS_IPHONE
        NSNumber* categoryIndex = (NSNumber*)call.arguments;
        AVAudioSessionCategory category = nil;
        switch (categoryIndex.integerValue) {
            case 0: category = AVAudioSessionCategoryAmbient; break;
            case 1: category = AVAudioSessionCategorySoloAmbient; break;
            case 2: category = AVAudioSessionCategoryPlayback; break;
            case 3: category = AVAudioSessionCategoryRecord; break;
            case 4: category = AVAudioSessionCategoryPlayAndRecord; break;
            case 5: category = AVAudioSessionCategoryMultiRoute; break;
        }
        if (category) {
            _configuredSession = YES;
        }
        [[AVAudioSession sharedInstance] setCategory:category error:nil];
#endif
		result(nil);
	} else {
		result(FlutterMethodNotImplemented);
	}
}

@end
