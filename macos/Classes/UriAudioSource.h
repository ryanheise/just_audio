#import "IndexedAudioSource.h"
#import <FlutterMacOS/FlutterMacOS.h>

@interface UriAudioSource : IndexedAudioSource

- (instancetype)initWithId:(NSString *)sid uri:(NSString *)uri;

@end
