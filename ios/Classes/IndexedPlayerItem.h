#import <AVFoundation/AVFoundation.h>

@class IndexedAudioSource;

@interface IndexedPlayerItem : AVPlayerItem

@property (readwrite, nonatomic) IndexedAudioSource *audioSource;

@end
