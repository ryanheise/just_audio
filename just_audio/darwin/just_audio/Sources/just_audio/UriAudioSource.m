#import "./include/just_audio/UriAudioSource.h"
#import "./include/just_audio/IndexedAudioSource.h"
#import "./include/just_audio/IndexedPlayerItem.h"
#import "./include/just_audio/LoadControl.h"
#import "./include/just_audio/ResourceLoaderDelegate.h"
#import <AVFoundation/AVFoundation.h>

@implementation UriAudioSource {
    NSString *_uri;
    IndexedPlayerItem *_playerItem;
    IndexedPlayerItem *_playerItem2;
    /* CMTime _duration; */
    LoadControl *_loadControl;
    NSMutableDictionary *_headers;
    NSDictionary *_options;
    // Must keep a strong reference to the delegate, as AVAssetResourceLoader
    // only holds a weak reference.
    ResourceLoaderDelegate *_resourceLoaderDelegate;
    ResourceLoaderDelegate *_resourceLoaderDelegate2;
}

- (instancetype)initWithId:(NSString *)sid uri:(NSString *)uri loadControl:(LoadControl *)loadControl headers:(NSDictionary *)headers options:(NSDictionary *)options {
    self = [super initWithId:sid];
    NSAssert(self, @"super init cannot be nil");
    _uri = uri;
    _loadControl = loadControl;
    _headers = headers != (id)[NSNull null] ? [headers mutableCopy] : nil;
    _options = options;
    _resourceLoaderDelegate = nil;
    _resourceLoaderDelegate2 = nil;
    _playerItem = [self createPlayerItem:uri storeDelegate:YES isPrimary:YES];
    _playerItem2 = nil;
    return self;
}

- (NSString *)uri {
    return _uri;
}

- (IndexedPlayerItem *)createPlayerItem:(NSString *)uri storeDelegate:(BOOL)storeDelegate isPrimary:(BOOL)isPrimary {
    IndexedPlayerItem *item;
    NSMutableDictionary *assetOptions = [[NSMutableDictionary alloc] init];
    
    if (_options != (id)[NSNull null]) {
        NSDictionary *darwinOptions = _options[@"darwinAssetOptions"];
        if (darwinOptions != (id)[NSNull null]) {
            assetOptions[AVURLAssetPreferPreciseDurationAndTimingKey] = darwinOptions[@"preferPreciseDurationAndTiming"];
        }
    }
    
    if ([uri hasPrefix:@"file://"]) {
        NSURL *fileURL = [NSURL fileURLWithPath:[[uri stringByRemovingPercentEncoding] substringFromIndex:7]];
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:fileURL options:assetOptions];
        item = [[IndexedPlayerItem alloc] initWithAsset:asset];
    } else {
        if (_headers) {
            // Use user-agent key if it is the only header and the API is supported.
            if ([_headers count] == 1) {
                if (@available(macOS 13.0, iOS 16.0, *)) {
                    NSString *userAgent = _headers[@"User-Agent"];
                    if (userAgent) {
                        [_headers removeObjectForKey:@"User-Agent"];
                    } else {
                        userAgent = _headers[@"user-agent"];
                        if (userAgent) {
                            [_headers removeObjectForKey:@"user-agent"];
                        }
                    }
                    if (userAgent) {
                        assetOptions[AVURLAssetHTTPUserAgentKey] = userAgent;
                    }
                }
            }
            if ([_headers count] > 0) {
                assetOptions[@"AVURLAssetHTTPHeaderFieldsKey"] = _headers;
            }
        }
        
        // For HTTP(S) URLs, use a custom URL scheme with AVAssetResourceLoaderDelegate
        // to intercept and handle network requests ourselves via NSURLSession.
        // This is necessary because iOS 17+ changed the URL parser (RFC 3986) which
        // normalizes percent-encoded characters (e.g. %2B → +, %3D → =) breaking
        // signed/verified URLs. By handling requests ourselves, we preserve the
        // exact URL encoding.
        BOOL useResourceLoader = [uri hasPrefix:@"http://"] || [uri hasPrefix:@"https://"];

        if (useResourceLoader) {
            NSString *interceptedURI = [ResourceLoaderDelegate interceptedURLString:uri];
            NSURL *interceptedURL = [NSURL URLWithString:interceptedURI];
            if (!interceptedURL) {
                NSLog(@"just_audio: ResourceLoader: Failed to create intercepted URL from: %@", interceptedURI);
                // Fallback to direct loading
                useResourceLoader = NO;
            } else {
                ResourceLoaderDelegate *delegate = [[ResourceLoaderDelegate alloc]
                    initWithOriginalURLString:uri
                    headers:(_headers && [_headers count] > 0) ? _headers : nil];

                AVURLAsset *asset = [AVURLAsset URLAssetWithURL:interceptedURL options:assetOptions];
                [asset.resourceLoader setDelegate:delegate queue:dispatch_get_main_queue()];

                // Store a strong reference to the delegate (AVAssetResourceLoader only
                // holds a weak reference).
                if (storeDelegate) {
                    if (isPrimary) {
                        _resourceLoaderDelegate = delegate;
                    } else {
                        _resourceLoaderDelegate2 = delegate;
                    }
                }

                item = [[IndexedPlayerItem alloc] initWithAsset:asset];
            }
        }

        if (!useResourceLoader) {
            // Fallback: direct URL loading (for non-HTTP or if interception failed).
            // Still try to preserve percent-encoding via NSURLComponents.
            NSURL *url = nil;
            NSURLComponents *components = [NSURLComponents componentsWithString:uri];
            if (components) {
                NSRange queryRange = [uri rangeOfString:@"?"];
                if (queryRange.location != NSNotFound) {
                    NSString *rawQuery = [uri substringFromIndex:queryRange.location + 1];
                    NSRange fragmentRange = [rawQuery rangeOfString:@"#"];
                    if (fragmentRange.location != NSNotFound) {
                        rawQuery = [rawQuery substringToIndex:fragmentRange.location];
                    }
                    components.percentEncodedQuery = rawQuery;
                }
                url = components.URL;
            }
            if (!url) {
                url = [NSURL URLWithString:uri];
            }
            if (!url) {
                NSLog(@"just_audio: ERROR: Failed to create NSURL from URI: %@", uri);
                url = [NSURL URLWithString:@"about:blank"];
            }
            AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:assetOptions];
            item = [[IndexedPlayerItem alloc] initWithAsset:asset];
        }
    }
    if (@available(macOS 10.13, iOS 11.0, *)) {
        // This does the best at reducing distortion on voice with speeds below 1.0
        item.audioTimePitchAlgorithm = AVAudioTimePitchAlgorithmTimeDomain;
    }
    if (@available(macOS 10.12, iOS 10.0, *)) {
        if (_loadControl.preferredForwardBufferDuration != (id)[NSNull null]) {
            item.preferredForwardBufferDuration = (double)([_loadControl.preferredForwardBufferDuration longLongValue]/1000) / 1000.0;
        }
    }
    if (@available(iOS 9.0, macOS 10.11, *)) {
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = _loadControl.canUseNetworkResourcesForLiveStreamingWhilePaused;
    }
    if (@available(iOS 8.0, macOS 10.10, *)) {
        if (_loadControl.preferredPeakBitRate != (id)[NSNull null]) {
            item.preferredPeakBitRate = [_loadControl.preferredPeakBitRate doubleValue];
        }
    }

    return item;
}

// Not used. XXX: Remove?
- (void)applyPreferredForwardBufferDuration {
    if (@available(macOS 10.12, iOS 10.0, *)) {
        if (_loadControl.preferredForwardBufferDuration != (id)[NSNull null]) {
            double value = (double)([_loadControl.preferredForwardBufferDuration longLongValue]/1000) / 1000.0;
            _playerItem.preferredForwardBufferDuration = value;
            if (_playerItem2) {
                _playerItem2.preferredForwardBufferDuration = value;
            }
        }
    }
}

- (void)applyCanUseNetworkResourcesForLiveStreamingWhilePaused {
    if (@available(iOS 9.0, macOS 10.11, *)) {
        _playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = _loadControl.canUseNetworkResourcesForLiveStreamingWhilePaused;
        if (_playerItem2) {
            _playerItem2.canUseNetworkResourcesForLiveStreamingWhilePaused = _loadControl.canUseNetworkResourcesForLiveStreamingWhilePaused;
        }
    }
}

- (void)applyPreferredPeakBitRate {
    if (@available(iOS 8.0, macOS 10.10, *)) {
        if (_loadControl.preferredPeakBitRate != (id)[NSNull null]) {
            double value = [_loadControl.preferredPeakBitRate doubleValue];
            _playerItem.preferredPeakBitRate = value;
            if (_playerItem2) {
                _playerItem2.preferredPeakBitRate = value;
            }
        }
    }
}

- (IndexedPlayerItem *)playerItem {
    return _playerItem;
}

- (IndexedPlayerItem *)playerItem2 {
    return _playerItem2;
}

- (NSArray<NSNumber *> *)getShuffleIndices {
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
        NSValue *seekableRange = _playerItem.seekableTimeRanges.lastObject;
        if (seekableRange) {
            CMTimeRange range = [seekableRange CMTimeRangeValue];
            position = CMTimeAdd(position, range.start);
        }
        [_playerItem seekToTime:position toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:completionHandler];
    } else {
        [super seek:position completionHandler:completionHandler];
    }
}

- (void)flip {
    IndexedPlayerItem *temp = _playerItem;
    _playerItem = _playerItem2;
    _playerItem2 = temp;
    // Also swap the resource loader delegates
    ResourceLoaderDelegate *tempDelegate = _resourceLoaderDelegate;
    _resourceLoaderDelegate = _resourceLoaderDelegate2;
    _resourceLoaderDelegate2 = tempDelegate;
}

- (void)preparePlayerItem2 {
    if (!_playerItem2) {
        _playerItem2 = [self createPlayerItem:_uri storeDelegate:YES isPrimary:NO];
        _playerItem2.audioSource = _playerItem.audioSource;
    }
}

- (CMTime)duration {
    NSValue *seekableRange = _playerItem.seekableTimeRanges.lastObject;
    if (seekableRange) {
        CMTimeRange seekableDuration = [seekableRange CMTimeRangeValue];
        return seekableDuration.duration;
    }
    else {
        return _playerItem.duration;
    }
    return kCMTimeInvalid;
}

- (void)setDuration:(CMTime)duration {
}

- (CMTime)position {
    NSValue *seekableRange = _playerItem.seekableTimeRanges.lastObject;
    if (seekableRange) {
        CMTimeRange range = [seekableRange CMTimeRangeValue];
        return CMTimeSubtract(_playerItem.currentTime, range.start);
    } else {
        return _playerItem.currentTime;
    }
    
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
