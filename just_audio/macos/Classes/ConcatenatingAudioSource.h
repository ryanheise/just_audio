#import "AudioSource.h"
#import <FlutterMacOS/FlutterMacOS.h>

@interface ConcatenatingAudioSource : AudioSource

@property (readonly, nonatomic) int count;

- (instancetype)initWithId:(NSString *)sid audioSources:(NSMutableArray<AudioSource *> *)audioSources;
- (void)insertSource:(AudioSource *)audioSource atIndex:(int)index;
- (void)removeSourcesFromIndex:(int)start toIndex:(int)end;
- (void)moveSourceFromIndex:(int)currentIndex toIndex:(int)newIndex;

@end
