#import "JustAudioPlugin.h"
#if __has_include(<just_audio/just_audio-Swift.h>)
#import <just_audio/just_audio-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "just_audio-Swift.h"
#endif

#import <AVFoundation/AVFoundation.h>

@implementation JustAudioPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    if (@available(iOS 13.0, *)) {
        [SwiftJustAudioPlugin registerWithRegistrar:registrar];
    } else {
        // Fallback on earlier versions
    }
}
@end
