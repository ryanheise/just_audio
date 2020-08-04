#import "UriAudioSource.h"
#import "IndexedAudioSource.h"
#import "IndexedPlayerItem.h"
#import <AVFoundation/AVFoundation.h>

@implementation UriAudioSource {
    NSString *_uri;
    IndexedPlayerItem *_playerItem;
    /* CMTime _duration; */
}

- (instancetype)initWithId:(NSString *)sid uri:(NSString *)uri {
    self = [super initWithId:sid];
    NSAssert(self, @"super init cannot be nil");
    _uri = uri;
    if ([_uri hasPrefix:@"file://"]) {
        _playerItem = [[IndexedPlayerItem alloc] initWithURL:[NSURL fileURLWithPath:[_uri substringFromIndex:7]]];
    } else {
        _playerItem = [[IndexedPlayerItem alloc] initWithURL:[NSURL URLWithString:_uri]];
    }
    if (@available(macOS 10.13, iOS 11.0, *)) {
        // This does the best at reducing distortion on voice with speeds below 1.0
        _playerItem.audioTimePitchAlgorithm = AVAudioTimePitchAlgorithmTimeDomain;
    }
    /* NSKeyValueObservingOptions options = */
    /*     NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew; */
    /* [_playerItem addObserver:self */
    /*               forKeyPath:@"duration" */
    /*                  options:options */
    /*                  context:nil]; */
    return self;
}

- (IndexedPlayerItem *)playerItem {
    return _playerItem;
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
    if (!completionHandler || (_playerItem.status == AVPlayerItemStatusReadyToPlay)) {
        [_playerItem seekToTime:position toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:completionHandler];
    }
}

- (CMTime)duration {
    return _playerItem.duration;
}

- (void)setDuration:(CMTime)duration {
}

- (CMTime)position {
    return _playerItem.currentTime;
}

- (CMTime)bufferedPosition {
    NSValue *last = _playerItem.loadedTimeRanges.lastObject;
    if (last) {
        CMTimeRange timeRange = [last CMTimeRangeValue];
        return CMTimeAdd(timeRange.start, timeRange.duration);
    } else {
        return _playerItem.currentTime;
    }
    return kCMTimeInvalid;
}

@end
