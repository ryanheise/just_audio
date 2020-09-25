#import "IndexedAudioSource.h"
#import <Flutter/Flutter.h>

@interface UriAudioSource : IndexedAudioSource

- (instancetype)initWithId:(NSString *)sid uri:(NSString *)uri;

@end
