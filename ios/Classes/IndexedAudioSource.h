#import "AudioSource.h"
#import "IndexedPlayerItem.h"
#import <Flutter/Flutter.h>
#import <AVFoundation/AVFoundation.h>

@interface IndexedAudioSource : AudioSource

@property (readonly, nonatomic) IndexedPlayerItem *playerItem;
@property (readwrite, nonatomic) CMTime duration;
@property (readonly, nonatomic) CMTime position;
@property (readonly, nonatomic) CMTime bufferedPosition;
@property (readonly, nonatomic) BOOL isAttached;

- (void)attach:(AVQueuePlayer *)player;
- (void)play:(AVQueuePlayer *)player;
- (void)pause:(AVQueuePlayer *)player;
- (void)stop:(AVQueuePlayer *)player;
- (void)seek:(CMTime)position;
- (void)seek:(CMTime)position completionHandler:(void (^)(BOOL))completionHandler;

@end
