#import "AudioSource.h"
#import "UriAudioSource.h"
#import <Flutter/Flutter.h>

@interface ClippingAudioSource : IndexedAudioSource

- (instancetype)initWithId:(NSString *)sid audioSource:(UriAudioSource *)audioSource start:(NSNumber *)start end:(NSNumber *)end;

@end
