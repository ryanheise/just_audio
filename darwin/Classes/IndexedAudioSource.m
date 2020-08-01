#import "IndexedAudioSource.h"
#import "IndexedPlayerItem.h"
#import <AVFoundation/AVFoundation.h>

@implementation IndexedAudioSource {
    BOOL _isAttached;
}

- (instancetype)initWithId:(NSString *)sid {
    self = [super init];
    NSAssert(self, @"super init cannot be nil");
    _isAttached = NO;
    return self;
}

- (IndexedPlayerItem *)playerItem {
    return nil;
}

- (BOOL)isAttached {
    return _isAttached;
}

- (int)buildSequence:(NSMutableArray *)sequence treeIndex:(int)treeIndex {
    [sequence addObject:self];
    return treeIndex + 1;
}

- (int)shuffle:(int)treeIndex currentIndex:(int)currentIndex {
    return treeIndex + 1;
}

- (void)attach:(AVQueuePlayer *)player {
    _isAttached = YES;
}

- (void)play:(AVQueuePlayer *)player {
}

- (void)pause:(AVQueuePlayer *)player {
}

- (void)stop:(AVQueuePlayer *)player {
}

- (void)seek:(CMTime)position {
    [self seek:position completionHandler:nil];
}

- (void)seek:(CMTime)position completionHandler:(void (^)(BOOL))completionHandler {
}

- (CMTime)duration {
    return kCMTimeInvalid;
}

- (void)setDuration:(CMTime)duration {
}

- (CMTime)position {
    return kCMTimeInvalid;
}

- (CMTime)bufferedPosition {
    return kCMTimeInvalid;
}

@end
