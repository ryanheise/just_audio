#import "IndexedPlayerItem.h"
#import "IndexedAudioSource.h"

@implementation IndexedPlayerItem {
    IndexedAudioSource *_audioSource;
}

-(void)setAudioSource:(IndexedAudioSource *)audioSource {
    _audioSource = audioSource;
}

-(IndexedAudioSource *)audioSource {
    return _audioSource;
}

@end
