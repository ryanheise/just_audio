#import "AudioPlayer.h"
#import "AudioSource.h"
#import "IndexedAudioSource.h"
#import "UriAudioSource.h"
#import "ConcatenatingAudioSource.h"
#import "LoopingAudioSource.h"
#import "ClippingAudioSource.h"
#import <AVFoundation/AVFoundation.h>
#import <stdlib.h>
#include <TargetConditionals.h>

// TODO: Check for and report invalid state transitions.
// TODO: Apply Apple's guidance on seeking: https://developer.apple.com/library/archive/qa/qa1820/_index.html
@implementation AudioPlayer {
    NSObject<FlutterPluginRegistrar>* _registrar;
    FlutterMethodChannel *_methodChannel;
    FlutterEventChannel *_eventChannel;
    FlutterEventSink _eventSink;
    NSString *_playerId;
    AVQueuePlayer *_player;
    AudioSource *_audioSource;
    NSMutableArray<IndexedAudioSource *> *_indexedAudioSources;
    NSMutableArray<NSNumber *> *_order;
    NSMutableArray<NSNumber *> *_orderInv;
    int _index;
    enum ProcessingState _processingState;
    enum LoopMode _loopMode;
    BOOL _shuffleModeEnabled;
    long long _updateTime;
    int _updatePosition;
    int _lastPosition;
    int _bufferedPosition;
    // Set when the current item hasn't been played yet so we aren't sure whether sufficient audio has been buffered.
    BOOL _bufferUnconfirmed;
    CMTime _seekPos;
    FlutterResult _loadResult;
    FlutterResult _playResult;
    id _timeObserver;
    BOOL _automaticallyWaitsToMinimizeStalling;
    BOOL _configuredSession;
    BOOL _playing;
}

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar playerId:(NSString*)idParam configuredSession:(BOOL)configuredSession {
    self = [super init];
    NSAssert(self, @"super init cannot be nil");
    _registrar = registrar;
    _playerId = idParam;
    _configuredSession = configuredSession;
    _methodChannel =
        [FlutterMethodChannel methodChannelWithName:[NSMutableString stringWithFormat:@"com.ryanheise.just_audio.methods.%@", _playerId]
                                    binaryMessenger:[registrar messenger]];
    _eventChannel =
        [FlutterEventChannel eventChannelWithName:[NSMutableString stringWithFormat:@"com.ryanheise.just_audio.events.%@", _playerId]
                                  binaryMessenger:[registrar messenger]];
    [_eventChannel setStreamHandler:self];
    _index = 0;
    _processingState = none;
    _loopMode = loopOff;
    _shuffleModeEnabled = NO;
    _player = nil;
    _audioSource = nil;
    _indexedAudioSources = nil;
    _order = nil;
    _orderInv = nil;
    _seekPos = kCMTimeInvalid;
    _timeObserver = 0;
    _updatePosition = 0;
    _updateTime = 0;
    _lastPosition = 0;
    _bufferedPosition = 0;
    _bufferUnconfirmed = NO;
    _playing = NO;
    _loadResult = nil;
    _playResult = nil;
    _automaticallyWaitsToMinimizeStalling = YES;
    __weak __typeof__(self) weakSelf = self;
    [_methodChannel setMethodCallHandler:^(FlutterMethodCall* call, FlutterResult result) {
        [weakSelf handleMethodCall:call result:result];
    }];
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSArray* args = (NSArray*)call.arguments;
    if ([@"load" isEqualToString:call.method]) {
        [self load:args[0] result:result];
    } else if ([@"play" isEqualToString:call.method]) {
        [self play:result];
    } else if ([@"pause" isEqualToString:call.method]) {
        [self pause];
        result(nil);
    } else if ([@"setVolume" isEqualToString:call.method]) {
        [self setVolume:(float)[args[0] doubleValue]];
        result(nil);
    } else if ([@"setSpeed" isEqualToString:call.method]) {
        [self setSpeed:(float)[args[0] doubleValue]];
        result(nil);
    } else if ([@"setLoopMode" isEqualToString:call.method]) {
        [self setLoopMode:[args[0] intValue]];
        result(nil);
    } else if ([@"setShuffleModeEnabled" isEqualToString:call.method]) {
        [self setShuffleModeEnabled:(BOOL)[args[0] boolValue]];
        result(nil);
    } else if ([@"setAutomaticallyWaitsToMinimizeStalling" isEqualToString:call.method]) {
        [self setAutomaticallyWaitsToMinimizeStalling:(BOOL)[args[0] boolValue]];
        result(nil);
    } else if ([@"seek" isEqualToString:call.method]) {
        CMTime position = args[0] == [NSNull null] ? kCMTimePositiveInfinity : CMTimeMake([args[0] intValue], 1000);
        [self seek:position index:args[1] completionHandler:^(BOOL finished) {
            result(nil);
        }];
        result(nil);
    } else if ([@"dispose" isEqualToString:call.method]) {
        [self dispose];
        result(nil);
    } else if ([@"concatenating.add" isEqualToString:call.method]) {
        [self concatenatingAdd:(NSString*)args[0] source:(NSDictionary*)args[1]];
        result(nil);
    } else if ([@"concatenating.insert" isEqualToString:call.method]) {
        [self concatenatingInsert:(NSString*)args[0] index:[args[1] intValue] source:(NSDictionary*)args[2]];
        result(nil);
    } else if ([@"concatenating.addAll" isEqualToString:call.method]) {
        [self concatenatingAddAll:(NSString*)args[0] sources:(NSArray*)args[1]];
        result(nil);
    } else if ([@"concatenating.insertAll" isEqualToString:call.method]) {
        [self concatenatingInsertAll:(NSString*)args[0] index:[args[1] intValue] sources:(NSArray*)args[2]];
        result(nil);
    } else if ([@"concatenating.removeAt" isEqualToString:call.method]) {
        [self concatenatingRemoveAt:(NSString*)args[0] index:(int)args[1]];
        result(nil);
    } else if ([@"concatenating.removeRange" isEqualToString:call.method]) {
        [self concatenatingRemoveRange:(NSString*)args[0] start:[args[1] intValue] end:[args[2] intValue]];
        result(nil);
    } else if ([@"concatenating.move" isEqualToString:call.method]) {
        [self concatenatingMove:(NSString*)args[0] currentIndex:[args[1] intValue] newIndex:[args[2] intValue]];
        result(nil);
    } else if ([@"concatenating.clear" isEqualToString:call.method]) {
        [self concatenatingClear:(NSString*)args[0]];
        result(nil);
    } else {
        result(FlutterMethodNotImplemented);
    }
}

// Untested
- (void)concatenatingAdd:(NSString *)catId source:(NSDictionary *)source {
    [self concatenatingInsertAll:catId index:-1 sources:@[source]];
}

// Untested
- (void)concatenatingInsert:(NSString *)catId index:(int)index source:(NSDictionary *)source {
    [self concatenatingInsertAll:catId index:index sources:@[source]];
}

// Untested
- (void)concatenatingAddAll:(NSString *)catId sources:(NSArray *)sources {
    [self concatenatingInsertAll:catId index:-1 sources:sources];
}

// Untested
- (void)concatenatingInsertAll:(NSString *)catId index:(int)index sources:(NSArray *)sources {
    // Find all duplicates of the identified ConcatenatingAudioSource.
    NSMutableArray *matches = [[NSMutableArray alloc] init];
    [_audioSource findById:catId matches:matches];
    // Add each new source to each match.
    for (int i = 0; i < matches.count; i++) {
        ConcatenatingAudioSource *catSource = (ConcatenatingAudioSource *)matches[i];
        int idx = index >= 0 ? index : catSource.count;
        NSMutableArray<AudioSource *> *audioSources = [self decodeAudioSources:sources];
        for (int j = 0; j < audioSources.count; j++) {
            AudioSource *audioSource = audioSources[j];
            [catSource insertSource:audioSource atIndex:(idx + j)];
        }
    }
    // Index the new audio sources.
    _indexedAudioSources = [[NSMutableArray alloc] init];
    [_audioSource buildSequence:_indexedAudioSources treeIndex:0];
    for (int i = 0; i < [_indexedAudioSources count]; i++) {
        IndexedAudioSource *audioSource = _indexedAudioSources[i];
        if (!audioSource.isAttached) {
            audioSource.playerItem.audioSource = audioSource;
            [self addItemObservers:audioSource.playerItem];
        }
    }
    [self updateOrder];
    if (_player.currentItem) {
        _index = [self indexForItem:_player.currentItem];
    } else {
        _index = 0;
    }
    [self enqueueFrom:_index];
    // Notify each new IndexedAudioSource that it's been attached to the player.
    for (int i = 0; i < [_indexedAudioSources count]; i++) {
        if (!_indexedAudioSources[i].isAttached) {
            [_indexedAudioSources[i] attach:_player];
        }
    }
    [self broadcastPlaybackEvent];
}

// Untested
- (void)concatenatingRemoveAt:(NSString *)catId index:(int)index {
    [self concatenatingRemoveRange:catId start:index end:(index + 1)];
}

// Untested
- (void)concatenatingRemoveRange:(NSString *)catId start:(int)start end:(int)end {
    // Find all duplicates of the identified ConcatenatingAudioSource.
    NSMutableArray *matches = [[NSMutableArray alloc] init];
    [_audioSource findById:catId matches:matches];
    // Remove range from each match.
    for (int i = 0; i < matches.count; i++) {
        ConcatenatingAudioSource *catSource = (ConcatenatingAudioSource *)matches[i];
        int endIndex = end >= 0 ? end : catSource.count;
        [catSource removeSourcesFromIndex:start toIndex:endIndex];
    }
    // Re-index the remaining audio sources.
    NSArray<IndexedAudioSource *> *oldIndexedAudioSources = _indexedAudioSources;
    _indexedAudioSources = [[NSMutableArray alloc] init];
    [_audioSource buildSequence:_indexedAudioSources treeIndex:0];
    for (int i = 0, j = 0; i < _indexedAudioSources.count; i++, j++) {
        IndexedAudioSource *audioSource = _indexedAudioSources[i];
        while (audioSource != oldIndexedAudioSources[j]) {
            [self removeItemObservers:oldIndexedAudioSources[j].playerItem];
            if (j < _index) {
                _index--;
            } else if (j == _index) {
                // The currently playing item was removed.
            }
            j++;
        }
    }
    [self updateOrder];
    if (_index >= _indexedAudioSources.count) _index = _indexedAudioSources.count - 1;
    if (_index < 0) _index = 0;
    [self enqueueFrom:_index];
    [self broadcastPlaybackEvent];
}

// Untested
- (void)concatenatingMove:(NSString *)catId currentIndex:(int)currentIndex newIndex:(int)newIndex {
    // Find all duplicates of the identified ConcatenatingAudioSource.
    NSMutableArray *matches = [[NSMutableArray alloc] init];
    [_audioSource findById:catId matches:matches];
    // Move range within each match.
    for (int i = 0; i < matches.count; i++) {
        ConcatenatingAudioSource *catSource = (ConcatenatingAudioSource *)matches[i];
        [catSource moveSourceFromIndex:currentIndex toIndex:newIndex];
    }
    // Re-index the audio sources.
    _indexedAudioSources = [[NSMutableArray alloc] init];
    [_audioSource buildSequence:_indexedAudioSources treeIndex:0];
    _index = [self indexForItem:_player.currentItem];
    [self broadcastPlaybackEvent];
}

// Untested
- (void)concatenatingClear:(NSString *)catId {
    [self concatenatingRemoveRange:catId start:0 end:-1];
}

- (FlutterError*)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)eventSink {
    _eventSink = eventSink;
    return nil;
}

- (FlutterError*)onCancelWithArguments:(id)arguments {
    _eventSink = nil;
    return nil;
}

- (void)checkForDiscontinuity {
    if (!_eventSink) return;
    if (!_playing || CMTIME_IS_VALID(_seekPos) || _processingState == completed) return;
    int position = [self getCurrentPosition];
    if (_processingState == buffering) {
        if (position > _lastPosition) {
            [self leaveBuffering:@"stall ended"];
            [self updatePosition];
            [self broadcastPlaybackEvent];
        }
    } else {
        long long now = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
        long long timeSinceLastUpdate = now - _updateTime;
        long long expectedPosition = _updatePosition + (long long)(timeSinceLastUpdate * _player.rate);
        long long drift = position - expectedPosition;
        //NSLog(@"position: %d, drift: %lld", position, drift);
        // Update if we've drifted or just started observing
        if (_updateTime == 0L) {
            [self broadcastPlaybackEvent];
        } else if (drift < -100) {
            [self enterBuffering:@"stalling"];
            NSLog(@"Drift: %lld", drift);
            [self updatePosition];
            [self broadcastPlaybackEvent];
        }
    }
    _lastPosition = position;
}

- (void)enterBuffering:(NSString *)reason {
    NSLog(@"ENTER BUFFERING: %@", reason);
    _processingState = buffering;
}

- (void)leaveBuffering:(NSString *)reason {
    NSLog(@"LEAVE BUFFERING: %@", reason);
    _processingState = ready;
}

- (void)broadcastPlaybackEvent {
    if (!_eventSink) return;
    _eventSink(@{
            @"processingState": @(_processingState),
            @"updatePosition": @(_updatePosition),
            @"updateTime": @(_updateTime),
            // TODO: buffer position
            @"bufferedPosition": @(_updatePosition),
            // TODO: Icy Metadata
            @"icyMetadata": [NSNull null],
            @"duration": @([self getDuration]),
            @"currentIndex": @(_index),
    });
}

- (int)getCurrentPosition {
    if (_processingState == none || _processingState == loading) {
        return 0;
    } else if (CMTIME_IS_VALID(_seekPos)) {
        return (int)(1000 * CMTimeGetSeconds(_seekPos));
    } else if (_indexedAudioSources) {
        int ms = (int)(1000 * CMTimeGetSeconds(_indexedAudioSources[_index].position));
        if (ms < 0) ms = 0;
        return ms;
    } else {
        return 0;
    }
}

- (int)getBufferedPosition {
    if (_processingState == none || _processingState == loading) {
        return 0;
    } else if (_indexedAudioSources) {
        int ms = (int)(1000 * CMTimeGetSeconds(_indexedAudioSources[_index].bufferedPosition));
        if (ms < 0) ms = 0;
        return ms;
    } else {
        return 0;
    }
}

- (int)getDuration {
    if (_processingState == none) {
        return -1;
    } else if (_indexedAudioSources) {
        int v = (int)(1000 * CMTimeGetSeconds(_indexedAudioSources[_index].duration));
        return v;
    } else {
        return 0;
    }
}

- (void)removeItemObservers:(AVPlayerItem *)playerItem {
    [playerItem removeObserver:self forKeyPath:@"status"];
    [playerItem removeObserver:self forKeyPath:@"playbackBufferEmpty"];
    [playerItem removeObserver:self forKeyPath:@"playbackBufferFull"];
    //[playerItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp"];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:playerItem];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:playerItem];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemPlaybackStalledNotification object:playerItem];
}

- (void)addItemObservers:(AVPlayerItem *)playerItem {
    // Get notified when the item is loaded or had an error loading
    [playerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    // Get notified of the buffer state
    [playerItem addObserver:self forKeyPath:@"playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:nil];
    [playerItem addObserver:self forKeyPath:@"playbackBufferFull" options:NSKeyValueObservingOptionNew context:nil];
    [playerItem addObserver:self forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionNew context:nil];
    //[playerItem addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:NSKeyValueObservingOptionNew context:nil];
    // Get notified when playback has reached the end
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onComplete:) name:AVPlayerItemDidPlayToEndTimeNotification object:playerItem];
    // Get notified when playback stops due to a failure (currently unused)
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onFailToComplete:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:playerItem];
    // Get notified when playback stalls (currently unused)
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onItemStalled:) name:AVPlayerItemPlaybackStalledNotification object:playerItem];
}

- (NSMutableArray *)decodeAudioSources:(NSArray *)data {
    NSMutableArray *array = [[NSMutableArray alloc] init];
    for (int i = 0; i < [data count]; i++) {
        AudioSource *source = [self decodeAudioSource:data[i]];
        [array addObject:source];
    }
    return array;
}

- (AudioSource *)decodeAudioSource:(NSDictionary *)data {
    NSString *type = data[@"type"];
    if ([@"progressive" isEqualToString:type]) {
        return [[UriAudioSource alloc] initWithId:data[@"id"] uri:data[@"uri"]];
    } else if ([@"dash" isEqualToString:type]) {
        return [[UriAudioSource alloc] initWithId:data[@"id"] uri:data[@"uri"]];
    } else if ([@"hls" isEqualToString:type]) {
        return [[UriAudioSource alloc] initWithId:data[@"id"] uri:data[@"uri"]];
    } else if ([@"concatenating" isEqualToString:type]) {
        return [[ConcatenatingAudioSource alloc] initWithId:data[@"id"]
                                               audioSources:[self decodeAudioSources:data[@"audioSources"]]];
    } else if ([@"clipping" isEqualToString:type]) {
        return [[ClippingAudioSource alloc] initWithId:data[@"id"]
                                           audioSource:[self decodeAudioSource:data[@"audioSource"]]
                                                 start:data[@"start"]
                                                   end:data[@"end"]];
    } else if ([@"looping" isEqualToString:type]) {
        NSMutableArray *childSources = [NSMutableArray new];
        int count = [data[@"count"] intValue];
        for (int i = 0; i < count; i++) {
            [childSources addObject:[self decodeAudioSource:data[@"audioSource"]]];
        }
        return [[LoopingAudioSource alloc] initWithId:data[@"id"] audioSources:childSources];
    } else {
        return nil;
    }
}

- (void)enqueueFrom:(int)index {
    int oldIndex = _index;
    _index = index;

    // Update the queue while keeping the currently playing item untouched.

    /* NSLog(@"before reorder: _player.items.count: ", _player.items.count); */
    /* [self dumpQueue]; */

    // First, remove all _player items except for the currently playing one (if any).
    IndexedPlayerItem *oldItem = _player.currentItem;
    IndexedPlayerItem *existingItem = nil;
    NSArray *oldPlayerItems = [NSArray arrayWithArray:_player.items];
    // In the first pass, preserve the old and new items.
    for (int i = 0; i < oldPlayerItems.count; i++) {
        if (oldPlayerItems[i] == _indexedAudioSources[_index].playerItem) {
            // Preserve and tag new item if it is already in the queue.
            existingItem = oldPlayerItems[i];
        } else if (oldPlayerItems[i] == oldItem) {
            // Temporarily preserve old item, just to avoid jumping to
            // intermediate queue positions unnecessarily. We only want to jump
            // once to _index.
        } else {
            [_player removeItem:oldPlayerItems[i]];
        }
    }
    // In the second pass, remove the old item (if different from new item).
    if (_index != oldIndex) {
        [_player removeItem:oldItem];
    }

    /* NSLog(@"inter order: _player.items.count: ", _player.items.count); */
    /* [self dumpQueue]; */

    // Regenerate queue
    BOOL include = NO;
    for (int i = 0; i < [_order count]; i++) {
        int si = [_order[i] intValue];
        if (si == _index) include = YES;
        if (include && _indexedAudioSources[si].playerItem != existingItem) {
            [_player insertItem:_indexedAudioSources[si].playerItem afterItem:nil];
        }
    }

    /* NSLog(@"after reorder: _player.items.count: ", _player.items.count); */
    /* [self dumpQueue]; */

    if (_processingState != loading && oldItem != _indexedAudioSources[_index].playerItem) {
        // || !_player.currentItem.playbackLikelyToKeepUp;
        if (_player.currentItem.playbackBufferEmpty) {
            [self enterBuffering:@"enqueueFrom playbackBufferEmpty"];
        } else {
            [self leaveBuffering:@"enqueueFrom !playbackBufferEmpty"];
        }
        [self updatePosition];
    }
}

- (void)updatePosition {
    _updatePosition = [self getCurrentPosition];
    _updateTime = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
}

- (void)load:(NSDictionary *)source result:(FlutterResult)result {
    if (!_playing) {
        [_player pause];
    }
    if (_processingState == loading) {
        [self abortExistingConnection];
    }
    _loadResult = result;
    _index = 0;
    [self updatePosition];
    _processingState = loading;
    [self broadcastPlaybackEvent];
    // Remove previous observers
    if (_indexedAudioSources) {
        for (int i = 0; i < [_indexedAudioSources count]; i++) {
            [self removeItemObservers:_indexedAudioSources[i].playerItem];
        }
    }
    // Decode audio source
    if (_audioSource && [@"clipping" isEqualToString:source[@"type"]]) {
        // Check if we're clipping an audio source that was previously loaded.
        UriAudioSource *child = nil;
        if ([_audioSource isKindOfClass:[ClippingAudioSource class]]) {
            ClippingAudioSource *clipper = (ClippingAudioSource *)_audioSource;
            child = clipper.audioSource;
        } else if ([_audioSource isKindOfClass:[UriAudioSource class]]) {
            child = (UriAudioSource *)_audioSource;
        }
        if (child) {
            _audioSource = [[ClippingAudioSource alloc] initWithId:source[@"id"]
                                                       audioSource:child
                                                             start:source[@"start"]
                                                               end:source[@"end"]];
        } else {
            _audioSource = [self decodeAudioSource:source];
        }
    } else {
        _audioSource = [self decodeAudioSource:source];
    }
    _indexedAudioSources = [[NSMutableArray alloc] init];
    [_audioSource buildSequence:_indexedAudioSources treeIndex:0];
    for (int i = 0; i < [_indexedAudioSources count]; i++) {
        IndexedAudioSource *source = _indexedAudioSources[i];
        [self addItemObservers:source.playerItem];
        source.playerItem.audioSource = source;
    }
    [self updateOrder];
    // Set up an empty player
    if (!_player) {
        _player = [[AVQueuePlayer alloc] initWithItems:@[]];
        if (@available(macOS 10.12, iOS 10.0, *)) {
            _player.automaticallyWaitsToMinimizeStalling = _automaticallyWaitsToMinimizeStalling;
            // TODO: Remove these observers in dispose.
            [_player addObserver:self
                      forKeyPath:@"timeControlStatus"
                         options:NSKeyValueObservingOptionNew
                         context:nil];
        }
        [_player addObserver:self
                  forKeyPath:@"currentItem"
                     options:NSKeyValueObservingOptionNew
                     context:nil];
        // TODO: learn about the different ways to define weakSelf.
        //__weak __typeof__(self) weakSelf = self;
        //typeof(self) __weak weakSelf = self;
        __unsafe_unretained typeof(self) weakSelf = self;
        if (@available(macOS 10.12, iOS 10.0, *)) {}
        else {
            _timeObserver = [_player addPeriodicTimeObserverForInterval:CMTimeMake(200, 1000)
                                                                  queue:nil
                                                             usingBlock:^(CMTime time) {
                                                                 [weakSelf checkForDiscontinuity];
                                                             }
            ];
        }
    }
    // Initialise the AVQueuePlayer with items.
    [self enqueueFrom:0];
    // Notify each IndexedAudioSource that it's been attached to the player.
    for (int i = 0; i < [_indexedAudioSources count]; i++) {
        [_indexedAudioSources[i] attach:_player];
    }

    if (_player.currentItem.status == AVPlayerItemStatusReadyToPlay) {
        _loadResult(@([self getDuration]));
        _loadResult = nil;
    } else {
        // We send result after the playerItem is ready in observeValueForKeyPath.
    }
    [self broadcastPlaybackEvent];
}

- (void)updateOrder {
    if (_shuffleModeEnabled) {
        [_audioSource shuffle:0 currentIndex: _index];
    }
    _orderInv = [NSMutableArray arrayWithCapacity:[_indexedAudioSources count]];
    for (int i = 0; i < [_indexedAudioSources count]; i++) {
        [_orderInv addObject:@(0)];
    }
    if (_shuffleModeEnabled) {
        _order = [_audioSource getShuffleOrder];
    } else {
        NSMutableArray *order = [[NSMutableArray alloc] init];
        for (int i = 0; i < [_indexedAudioSources count]; i++) {
            [order addObject:@(i)];
        }
        _order = order;
    }
    for (int i = 0; i < [_indexedAudioSources count]; i++) {
        _orderInv[[_order[i] intValue]] = @(i);
    }
}

- (void)onItemStalled:(NSNotification *)notification {
    IndexedPlayerItem *playerItem = (IndexedPlayerItem *)notification.object;
    NSLog(@"onItemStalled");
}

- (void)onFailToComplete:(NSNotification *)notification {
    IndexedPlayerItem *playerItem = (IndexedPlayerItem *)notification.object;
    NSLog(@"onFailToComplete");
}

- (void)onComplete:(NSNotification *)notification {
    NSLog(@"onComplete");
    if (_loopMode == loopOne) {
        [self seek:kCMTimeZero index:@(_index) completionHandler:^(BOOL finished) {
            // XXX: Not necessary?
            [self play];
        }];
    } else {
        IndexedPlayerItem *endedPlayerItem = (IndexedPlayerItem *)notification.object;
        IndexedAudioSource *endedSource = endedPlayerItem.audioSource;
        // When an item ends, seek back to its beginning.
        [endedSource seek:kCMTimeZero];

        if ([_orderInv[_index] intValue] + 1 < [_order count]) {
            // account for automatic move to next item
            _index = [_order[[_orderInv[_index] intValue] + 1] intValue];
            NSLog(@"advance to next: index = %d", _index);
            [self broadcastPlaybackEvent];
        } else {
            // reached end of playlist
            if (_loopMode == loopAll) {
                NSLog(@"Loop back to first item");
                // Loop back to the beginning
                // TODO: Currently there will be a gap at the loop point.
                // Maybe we can do something clever by temporarily adding the
                // first playlist item at the end of the queue, although this
                // will affect any code that assumes the queue always
                // corresponds to a contiguous region of the indexed audio
                // sources.
                // For now we just do a seek back to the start.
                if ([_order count] == 1) {
                    [self seek:kCMTimeZero index:[NSNull null] completionHandler:^(BOOL finished) {
                        // XXX: Necessary?
                        [self play];
                    }];
                } else {
                    [self seek:kCMTimeZero index:_order[0] completionHandler:^(BOOL finished) {
                        // XXX: Necessary?
                        [self play];
                    }];
                }
            } else {
                [self complete];
            }
        }
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSString *,id> *)change
                       context:(void *)context {

    if ([keyPath isEqualToString:@"status"]) {
        IndexedPlayerItem *playerItem = (IndexedPlayerItem *)object;
        AVPlayerItemStatus status = AVPlayerItemStatusUnknown;
        NSNumber *statusNumber = change[NSKeyValueChangeNewKey];
        if ([statusNumber isKindOfClass:[NSNumber class]]) {
            status = statusNumber.intValue;
        }
        switch (status) {
            case AVPlayerItemStatusReadyToPlay: {
                if (playerItem != _player.currentItem) return;
                // Detect buffering in different ways depending on whether we're playing
                if (_playing) {
                    if (@available(macOS 10.12, iOS 10.0, *)) {
                        if (_player.timeControlStatus == AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate) {
                            [self enterBuffering:@"ready to play: playing, waitingToPlay"];
                        } else {
                            [self leaveBuffering:@"ready to play: playing, !waitingToPlay"];
                        }
                        [self updatePosition];
                    } else {
                        // If this happens when we're playing, check whether buffer is confirmed
                        if (_bufferUnconfirmed && !_player.currentItem.playbackBufferFull) {
                            // Stay in bufering - XXX Test
                            [self enterBuffering:@"ready to play: playing, bufferUnconfirmed && !playbackBufferFull"];
                        } else {
                            if (_player.currentItem.playbackBufferEmpty) {
                                // !_player.currentItem.playbackLikelyToKeepUp;
                                [self enterBuffering:@"ready to play: playing, playbackBufferEmpty"];
                            } else {
                                [self leaveBuffering:@"ready to play: playing, !playbackBufferEmpty"];
                            }
                            [self updatePosition];
                        }
                    }
                } else {
                    if (_player.currentItem.playbackBufferEmpty) {
                        [self enterBuffering:@"ready to play: !playing, playbackBufferEmpty"];
                        // || !_player.currentItem.playbackLikelyToKeepUp;
                    } else {
                        [self leaveBuffering:@"ready to play: !playing, !playbackBufferEmpty"];
                    }
                    [self updatePosition];
                }
                [self broadcastPlaybackEvent];
                if (_loadResult) {
                    _loadResult(@([self getDuration]));
                    _loadResult = nil;
                }
                break;
            }
            case AVPlayerItemStatusFailed: {
                NSLog(@"AVPlayerItemStatusFailed");
                [self sendErrorForItem:playerItem];
                break;
            }
            case AVPlayerItemStatusUnknown:
                break;
        }
    } else if ([keyPath isEqualToString:@"playbackBufferEmpty"] || [keyPath isEqualToString:@"playbackBufferFull"]) {
        // Use these values to detect buffering.
        IndexedPlayerItem *playerItem = (IndexedPlayerItem *)object;
        if (playerItem != _player.currentItem) return;
        // If there's a seek in progress, these values are unreliable
        if (CMTIME_IS_VALID(_seekPos)) return;
        // Detect buffering in different ways depending on whether we're playing
        if (_playing) {
            if (@available(macOS 10.12, iOS 10.0, *)) {
                // We handle this with timeControlStatus instead.
            } else {
                if (_bufferUnconfirmed && playerItem.playbackBufferFull) {
                    _bufferUnconfirmed = NO;
                    [self leaveBuffering:@"playing, _bufferUnconfirmed && playbackBufferFull"];
                    [self updatePosition];
                    NSLog(@"Buffering confirmed! leaving buffering");
                    [self broadcastPlaybackEvent];
                }
            }
        } else {
            if (playerItem.playbackBufferEmpty) {
                [self enterBuffering:@"!playing, playbackBufferEmpty"];
                [self updatePosition];
                [self broadcastPlaybackEvent];
            } else if (!playerItem.playbackBufferEmpty || playerItem.playbackBufferFull) {
                _processingState = ready;
                [self leaveBuffering:@"!playing, !playbackBufferEmpty || playbackBufferFull"];
                [self updatePosition];
                [self broadcastPlaybackEvent];
            }
        }
    /* } else if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"]) { */
    } else if ([keyPath isEqualToString:@"timeControlStatus"]) {
        if (@available(macOS 10.12, iOS 10.0, *)) {
            AVPlayerTimeControlStatus status = AVPlayerTimeControlStatusPaused;
            NSNumber *statusNumber = change[NSKeyValueChangeNewKey];
            if ([statusNumber isKindOfClass:[NSNumber class]]) {
                status = statusNumber.intValue;
            }
            switch (status) {
                case AVPlayerTimeControlStatusPaused:
                    //NSLog(@"AVPlayerTimeControlStatusPaused");
                    break;
                case AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate:
                    //NSLog(@"AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate");
                    if (_processingState != completed) {
                        [self enterBuffering:@"timeControlStatus"];
                        [self updatePosition];
                        [self broadcastPlaybackEvent];
                    } else {
                        NSLog(@"Ignoring wait signal because we reached the end");
                    }
                    break;
                case AVPlayerTimeControlStatusPlaying:
                    [self leaveBuffering:@"timeControlStatus"];
                    [self updatePosition];
                    [self broadcastPlaybackEvent];
                    break;
            }
        }
    } else if ([keyPath isEqualToString:@"currentItem"] && _player.currentItem) {
        if (_player.currentItem.status == AVPlayerItemStatusFailed) {
            if ([_orderInv[_index] intValue] + 1 < [_order count]) {
                // account for automatic move to next item
                _index = [_order[[_orderInv[_index] intValue] + 1] intValue];
                NSLog(@"advance to next on error: index = %d", _index);
                [self broadcastPlaybackEvent];
            } else {
                NSLog(@"error on last item");
            }
            return;
        } else {
            int expectedIndex = [self indexForItem:_player.currentItem];
            if (_index != expectedIndex) {
                // AVQueuePlayer will sometimes skip over error items without
                // notifying this observer.
                NSLog(@"Queue change detected. Adjusting index from %d -> %d", _index, expectedIndex);
                _index = expectedIndex;
                [self broadcastPlaybackEvent];
            }
        }
        //NSLog(@"currentItem changed. _index=%d", _index);
        _bufferUnconfirmed = YES;
        // If we've skipped or transitioned to a new item and we're not
        // currently in the middle of a seek
        if (CMTIME_IS_INVALID(_seekPos) && _player.currentItem.status == AVPlayerItemStatusReadyToPlay) {
            [self updatePosition];
            IndexedAudioSource *source = ((IndexedPlayerItem *)_player.currentItem).audioSource;
            // We should already be at position zero but for
            // ClippingAudioSource it might be off by some milliseconds so we
            // consider anything <= 100 as close enough.
            if ((int)(1000 * CMTimeGetSeconds(source.position)) > 100) {
                NSLog(@"On currentItem change, seeking back to zero");
                BOOL shouldResumePlayback = NO;
                AVPlayerActionAtItemEnd originalEndAction = _player.actionAtItemEnd;
                if (_playing && CMTimeGetSeconds(CMTimeSubtract(source.position, source.duration)) >= 0) {
                    NSLog(@"Need to pause while rewinding because we're at the end");
                    shouldResumePlayback = YES;
                    _player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
                    [_player pause];
                }
                [self enterBuffering:@"currentItem changed, seeking"];
                [self updatePosition];
                [self broadcastPlaybackEvent];
                [source seek:kCMTimeZero completionHandler:^(BOOL finished) {
                    [self leaveBuffering:@"currentItem changed, finished seek"];
                    [self updatePosition];
                    [self broadcastPlaybackEvent];
                    if (shouldResumePlayback) {
                        _player.actionAtItemEnd = originalEndAction;
                        // TODO: This logic is almost duplicated in seek. See if we can reuse this code.
                        [_player play];
                    }
                }];
            } else {
                // Already at zero, no need to seek.
            }
        }
    } else if ([keyPath isEqualToString:@"loadedTimeRanges"]) {
        IndexedPlayerItem *playerItem = (IndexedPlayerItem *)object;
        if (playerItem != _player.currentItem) return;
        int pos = [self getBufferedPosition];
        if (pos != _bufferedPosition) {
            _bufferedPosition = pos;
            [self broadcastPlaybackEvent];
        }
    }
}

- (void)sendErrorForItem:(IndexedPlayerItem *)playerItem {
    FlutterError *flutterError = [FlutterError errorWithCode:[NSString stringWithFormat:@"%d", playerItem.error.code]
                                                     message:playerItem.error.localizedDescription
                                                     details:nil];
    [self sendError:flutterError playerItem:playerItem];
}

- (void)sendError:(FlutterError *)flutterError playerItem:(IndexedPlayerItem *)playerItem {
    NSLog(@"sendError");
    if (_loadResult && playerItem == _player.currentItem) {
        _loadResult(flutterError);
        _loadResult = nil;
    }
    if (_eventSink) {
        // Broadcast all errors even if they aren't on the current item.
        _eventSink(flutterError);
    }
}

- (void)abortExistingConnection {
    FlutterError *flutterError = [FlutterError errorWithCode:@"abort"
                                                     message:@"Connection aborted"
                                                     details:nil];
    [self sendError:flutterError playerItem:nil];
}

- (int)indexForItem:(IndexedPlayerItem *)playerItem {
    for (int i = 0; i < _indexedAudioSources.count; i++) {
        if (_indexedAudioSources[i].playerItem == playerItem) {
            return i;
        }
    }
    return -1;
}

- (void)play {
    [self play:nil];
}

- (void)play:(FlutterResult)result {
    if (result) {
        if (_playResult) {
            NSLog(@"INTERRUPTING PLAY");
            _playResult(nil);
        }
        _playResult = result;
    }
    _playing = YES;
#if TARGET_OS_IPHONE
    if (_configuredSession) {
        [[AVAudioSession sharedInstance] setActive:YES error:nil];
    }
#endif
    [_player play];
    [self updatePosition];
    if (@available(macOS 10.12, iOS 10.0, *)) {}
    else {
        if (_bufferUnconfirmed && !_player.currentItem.playbackBufferFull) {
            [self enterBuffering:@"play, _bufferUnconfirmed && !playbackBufferFull"];
            [self broadcastPlaybackEvent];
        }
    }
}

- (void)pause {
    _playing = NO;
    [_player pause];
    [self updatePosition];
    [self broadcastPlaybackEvent];
    if (_playResult) {
        NSLog(@"PLAY FINISHED DUE TO PAUSE");
        _playResult(nil);
        _playResult = nil;
    }
}

- (void)complete {
    [self updatePosition];
    _processingState = completed;
    [self broadcastPlaybackEvent];
    if (_playResult) {
        NSLog(@"PLAY FINISHED DUE TO COMPLETE");
        _playResult(nil);
        _playResult = nil;
    }
}

- (void)setVolume:(float)volume {
    [_player setVolume:volume];
}

- (void)setSpeed:(float)speed {
    if (speed == 1.0
            || (speed < 1.0 && _player.currentItem.canPlaySlowForward)
            || (speed > 1.0 && _player.currentItem.canPlayFastForward)) {
        _player.rate = speed;
    }
    [self updatePosition];
}

- (void)setLoopMode:(int)loopMode {
    _loopMode = loopMode;
    if (_player) {
        switch (_loopMode) {
            case loopOne:
                _player.actionAtItemEnd = AVPlayerActionAtItemEndPause; // AVPlayerActionAtItemEndNone
                break;
            default:
                _player.actionAtItemEnd = AVPlayerActionAtItemEndAdvance;
        }
    }
}

- (void)setShuffleModeEnabled:(BOOL)shuffleModeEnabled {
    NSLog(@"setShuffleModeEnabled: %d", shuffleModeEnabled);
    _shuffleModeEnabled = shuffleModeEnabled;
    if (!_audioSource) return;

    [self updateOrder];

    [self enqueueFrom:_index];
}

- (void)dumpQueue {
    for (int i = 0; i < _player.items.count; i++) {
        IndexedPlayerItem *playerItem = _player.items[i];
        for (int j = 0; j < _indexedAudioSources.count; j++) {
            IndexedAudioSource *source = _indexedAudioSources[j];
            if (source.playerItem == playerItem) {
                NSLog(@"- %d", j);
                break;
            }
        }
    }
}

- (void)setAutomaticallyWaitsToMinimizeStalling:(bool)automaticallyWaitsToMinimizeStalling {
    _automaticallyWaitsToMinimizeStalling = automaticallyWaitsToMinimizeStalling;
    if (@available(macOS 10.12, iOS 10.0, *)) {
        if(_player) {
            _player.automaticallyWaitsToMinimizeStalling = automaticallyWaitsToMinimizeStalling;
        }
    }
}

- (void)seek:(CMTime)position index:(NSNumber *)newIndex completionHandler:(void (^)(BOOL))completionHandler {
    int index = _index;
    if (newIndex != [NSNull null]) {
        index = [newIndex intValue];
    }
    if (index != _index) {
        // Jump to a new item
        /* if (_playing && index == _index + 1) { */
        /*     // Special case for jumping to the very next item */
        /*     NSLog(@"seek to next item: %d -> %d", _index, index); */
        /*     [_indexedAudioSources[_index] seek:kCMTimeZero]; */
        /*     _index = index; */
        /*     [_player advanceToNextItem]; */
        /*     [self broadcastPlaybackEvent]; */
        /* } else */
        {
            // Jump to a distant item
            //NSLog(@"seek# jump to distant item: %d -> %d", _index, index);
            if (_playing) {
                [_player pause];
            }
            [_indexedAudioSources[_index] seek:kCMTimeZero];
            // The "currentItem" key observer will respect that a seek is already in progress
            _seekPos = position;
            [self updatePosition];
            [self enqueueFrom:index];
            IndexedAudioSource *source = _indexedAudioSources[_index];
            if (abs((int)(1000 * CMTimeGetSeconds(CMTimeSubtract(source.position, position)))) > 100) {
                [self enterBuffering:@"seek to index"];
                [self updatePosition];
                [self broadcastPlaybackEvent];
                [source seek:position completionHandler:^(BOOL finished) {
                    if (@available(macOS 10.12, iOS 10.0, *)) {
                        if (_playing) {
                            // Handled by timeControlStatus
                        } else {
                            if (_bufferUnconfirmed && !_player.currentItem.playbackBufferFull) {
                                // Stay in buffering
                            } else if (source.playerItem.status == AVPlayerItemStatusReadyToPlay) {
                                [self leaveBuffering:@"seek to index finished, (!bufferUnconfirmed || playbackBufferFull) && ready to play"];
                                [self updatePosition];
                                [self broadcastPlaybackEvent];
                            }
                        }
                    } else {
                        if (_bufferUnconfirmed && !_player.currentItem.playbackBufferFull) {
                            // Stay in buffering
                        } else if (source.playerItem.status == AVPlayerItemStatusReadyToPlay) {
                            [self leaveBuffering:@"seek to index finished, (!bufferUnconfirmed || playbackBufferFull) && ready to play"];
                            [self updatePosition];
                            [self broadcastPlaybackEvent];
                        }
                    }
                    if (_playing) {
                        [_player play];
                    }
                    _seekPos = kCMTimeInvalid;
                    [self broadcastPlaybackEvent];
                    if (completionHandler) {
                        completionHandler(finished);
                    }
                }];
            } else {
                _seekPos = kCMTimeInvalid;
                if (_playing) {
                    [_player play];
                }
            }
        }
    } else {
        // Seek within an item
        if (_playing) {
            [_player pause];
        }
        _seekPos = position;
        //NSLog(@"seek. enter buffering. pos = %d", (int)(1000*CMTimeGetSeconds(_indexedAudioSources[_index].position)));
        // TODO: Move this into a separate method so it can also
        // be used in skip.
        [self enterBuffering:@"seek"];
        [self updatePosition];
        [self broadcastPlaybackEvent];
        [_indexedAudioSources[_index] seek:position completionHandler:^(BOOL finished) {
            [self updatePosition];
            if (_playing) {
                // If playing, buffering will be detected either by:
                // 1. checkForDiscontinuity
                // 2. timeControlStatus
                [_player play];
            } else {
                // If not playing, there is no reliable way to detect
                // when buffering has completed, so we use
                // !playbackBufferEmpty. Although this always seems to
                // be full even right after a seek.
                if (_player.currentItem.playbackBufferEmpty) {
                    [self enterBuffering:@"seek finished, playbackBufferEmpty"];
                } else {
                    [self leaveBuffering:@"seek finished, !playbackBufferEmpty"];
                }
                [self updatePosition];
                if (_processingState != buffering) {
                    [self broadcastPlaybackEvent];
                }
            }
            _seekPos = kCMTimeInvalid;
            [self broadcastPlaybackEvent];
            if (completionHandler) {
                completionHandler(finished);
            }
        }];
    }
}

- (void)dispose {
    if (_processingState != none) {
        [_player pause];
        _processingState = none;
        [self broadcastPlaybackEvent];
    }
    if (_timeObserver) {
        [_player removeTimeObserver:_timeObserver];
        _timeObserver = 0;
    }
    if (_indexedAudioSources) {
        for (int i = 0; i < [_indexedAudioSources count]; i++) {
            [self removeItemObservers:_indexedAudioSources[i].playerItem];
        }
    }
    if (_player) {
        [_player removeObserver:self forKeyPath:@"currentItem"];
        if (@available(macOS 10.12, iOS 10.0, *)) {
            [_player removeObserver:self forKeyPath:@"timeControlStatus"];
        }
        _player = nil;
    }
    // Untested:
    // [_eventChannel setStreamHandler:nil];
    // [_methodChannel setMethodHandler:nil];
}

@end
