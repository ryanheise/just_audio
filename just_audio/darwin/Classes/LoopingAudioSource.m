#import "AudioSource.h"
#import "LoopingAudioSource.h"
#import <AVFoundation/AVFoundation.h>

@implementation LoopingAudioSource {
    // An array of duplicates
    NSArray<AudioSource *> *_audioSources; // <AudioSource *>
}

- (instancetype)initWithId:(NSString *)sid audioSources:(NSArray<AudioSource *> *)audioSources {
    self = [super initWithId:sid];
    NSAssert(self, @"super init cannot be nil");
    _audioSources = audioSources;
    return self;
}

- (int)buildSequence:(NSMutableArray *)sequence treeIndex:(int)treeIndex {
    for (int i = 0; i < [_audioSources count]; i++) {
        treeIndex = [_audioSources[i] buildSequence:sequence treeIndex:treeIndex];
    }
    return treeIndex;
}

- (void)findById:(NSString *)sourceId matches:(NSMutableArray<AudioSource *> *)matches {
    [super findById:sourceId matches:matches];
    for (int i = 0; i < [_audioSources count]; i++) {
        [_audioSources[i] findById:sourceId matches:matches];
    }
}

- (NSArray *)getShuffleOrder {
    NSMutableArray *order = [NSMutableArray new];
    int offset = (int)[order count];
    for (int i = 0; i < [_audioSources count]; i++) {
        AudioSource *audioSource = _audioSources[i];
        NSArray *childShuffleOrder = [audioSource getShuffleOrder];
        for (int j = 0; j < [childShuffleOrder count]; j++) {
            [order addObject:@([childShuffleOrder[j] integerValue] + offset)];
        }
        offset += [childShuffleOrder count];
    }
    return order;
}

- (int)shuffle:(int)treeIndex currentIndex:(int)currentIndex {
    // TODO: This should probably shuffle the same way on all duplicates.
    for (int i = 0; i < [_audioSources count]; i++) {
        treeIndex = [_audioSources[i] shuffle:treeIndex currentIndex:currentIndex];
    }
    return treeIndex;
}

@end
