#import "AudioSource.h"
#import "ClippingAudioSource.h"
#import "IndexedPlayerItem.h"
#import "UriAudioSource.h"
#import <AVFoundation/AVFoundation.h>

@implementation ClippingAudioSource {
    UriAudioSource *_audioSource;
    CMTime _start;
    CMTime _end;
}

- (instancetype)initWithId:(NSString *)sid audioSource:(UriAudioSource *)audioSource start:(NSNumber *)start end:(NSNumber *)end {
    self = [super initWithId:sid];
    NSAssert(self, @"super init cannot be nil");
    _audioSource = audioSource;
    _start = start == [NSNull null] ? kCMTimeZero : CMTimeMake([start intValue], 1000);
    _end = end == [NSNull null] ? kCMTimeInvalid : CMTimeMake([end intValue], 1000);
    return self;
}

- (UriAudioSource *)audioSource {
    return _audioSource;
}

- (void)findById:(NSString *)sourceId matches:(NSMutableArray<AudioSource *> *)matches {
    [super findById:sourceId matches:matches];
    [_audioSource findById:sourceId matches:matches];
}

- (void)attach:(AVQueuePlayer *)player {
    [super attach:player];
    _audioSource.playerItem.forwardPlaybackEndTime = _end;
    // XXX: Not needed since currentItem observer handles it?
    [self seek:kCMTimeZero];
}

- (IndexedPlayerItem *)playerItem {
    return _audioSource.playerItem;
}

- (NSArray *)getShuffleOrder {
    return @[@(0)];
}

- (void)play:(AVQueuePlayer *)player {
}

- (void)pause:(AVQueuePlayer *)player {
}

- (void)stop:(AVQueuePlayer *)player {
}

- (void)seek:(CMTime)position completionHandler:(void (^)(BOOL))completionHandler {
    if (!completionHandler || (self.playerItem.status == AVPlayerItemStatusReadyToPlay)) {
        CMTime absPosition = CMTimeAdd(_start, position);
        [_audioSource.playerItem seekToTime:absPosition toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:completionHandler];
    }
}

- (CMTime)duration {
    return CMTimeSubtract(CMTIME_IS_INVALID(_end) ? self.playerItem.duration : _end, _start);
}

- (void)setDuration:(CMTime)duration {
}

- (CMTime)position {
    return CMTimeSubtract(self.playerItem.currentTime, _start);
}

- (CMTime)bufferedPosition {
    CMTime pos = CMTimeSubtract(_audioSource.bufferedPosition, _start);
    CMTime dur = [self duration];
    return CMTimeCompare(pos, dur) >= 0 ? dur : pos;
}

@end
