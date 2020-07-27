#import "AudioSource.h"
#import "ConcatenatingAudioSource.h"
#import <AVFoundation/AVFoundation.h>
#import <stdlib.h>

@implementation ConcatenatingAudioSource {
    NSMutableArray<AudioSource *> *_audioSources;
    NSMutableArray<NSNumber *> *_shuffleOrder;
}

- (instancetype)initWithId:(NSString *)sid audioSources:(NSMutableArray<AudioSource *> *)audioSources {
    self = [super initWithId:sid];
    NSAssert(self, @"super init cannot be nil");
    _audioSources = audioSources;
    return self;
}

- (int)count {
    return _audioSources.count;
}

- (void)insertSource:(AudioSource *)audioSource atIndex:(int)index {
    [_audioSources insertObject:audioSource atIndex:index];
}

- (void)removeSourcesFromIndex:(int)start toIndex:(int)end {
    if (end == -1) end = _audioSources.count;
    for (int i = start; i < end; i++) {
        [_audioSources removeObjectAtIndex:start];
    }
}

- (void)moveSourceFromIndex:(int)currentIndex toIndex:(int)newIndex {
    AudioSource *source = _audioSources[currentIndex];
    [_audioSources removeObjectAtIndex:currentIndex];
    [_audioSources insertObject:source atIndex:newIndex];
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
    int offset = [order count];
    NSMutableArray *childOrders = [NSMutableArray new]; // array of array of ints
    for (int i = 0; i < [_audioSources count]; i++) {
        AudioSource *audioSource = _audioSources[i];
        NSArray *childShuffleOrder = [audioSource getShuffleOrder];
        NSMutableArray *offsetChildShuffleOrder = [NSMutableArray new];
        for (int j = 0; j < [childShuffleOrder count]; j++) {
            [offsetChildShuffleOrder addObject:@([childShuffleOrder[j] integerValue] + offset)];
        }
        [childOrders addObject:offsetChildShuffleOrder];
        offset += [childShuffleOrder count];
    }
    for (int i = 0; i < [_audioSources count]; i++) {
        [order addObjectsFromArray:childOrders[[_shuffleOrder[i] integerValue]]];
    }
    return order;
}

- (int)shuffle:(int)treeIndex currentIndex:(int)currentIndex {
    int currentChildIndex = -1;
    for (int i = 0; i < [_audioSources count]; i++) {
        int indexBefore = treeIndex;
        AudioSource *child = _audioSources[i];
        treeIndex = [child shuffle:treeIndex currentIndex:currentIndex];
        if (currentIndex >= indexBefore && currentIndex < treeIndex) {
            currentChildIndex = i;
        } else {}
    }
    // Shuffle so that the current child is first in the shuffle order
    _shuffleOrder = [NSMutableArray arrayWithCapacity:[_audioSources count]];
    for (int i = 0; i < [_audioSources count]; i++) {
        [_shuffleOrder addObject:@(0)];
    }
    NSLog(@"shuffle: audioSources.count=%d and shuffleOrder.count=%d", [_audioSources count], [_shuffleOrder count]);
    // First generate a random shuffle
    for (int i = 0; i < [_audioSources count]; i++) {
        int j = arc4random_uniform(i + 1);
        _shuffleOrder[i] = _shuffleOrder[j];
        _shuffleOrder[j] = @(i);
    }
    // Then bring currentIndex to the front
    if (currentChildIndex != -1) {
      for (int i = 1; i < [_audioSources count]; i++) {
        if ([_shuffleOrder[i] integerValue] == currentChildIndex) {
          NSNumber *v = _shuffleOrder[0];
          _shuffleOrder[0] = _shuffleOrder[i];
          _shuffleOrder[i] = v;
          break;
        }
      }
    }
    return treeIndex;
}

@end
