#import "EqualizedStreamPlayer.h"

// 10‑band graphic‑EQ centres (Hz), matching canonicalCentresHz.
static const double kBandCenters[10] = {31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000};
static const NSUInteger kNumBands = 10;
static const NSUInteger kMaxBuffered = 4;     // scheduled-ahead PCM buffers
static const NSUInteger kPacketsPerBuffer = 8; // ~8 AAC frames ≈ 8k PCM frames/buffer

#pragma mark - packet wrapper

@interface EqPacket : NSObject
@property (nonatomic, strong) NSData *data;
@property (nonatomic) AudioStreamPacketDescription desc;
@end
@implementation EqPacket
@end

#pragma mark - player

@interface EqualizedStreamPlayer () <NSURLSessionDataDelegate>
@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, strong) AVAudioPlayerNode *player;
@property (nonatomic, strong) AVAudioUnitEQ *eq;
@property (nonatomic, strong) AVAudioFormat *outFmt;
@property (nonatomic, strong) AVAudioFormat *convFmt;
@end

@implementation EqualizedStreamPlayer {
    AudioFileStreamID _streamID;
    AudioConverterRef _converter;
    BOOL _formatKnown;
    AudioStreamBasicDescription _inputFormat;
    AudioStreamBasicDescription _outputFormat;
    NSMutableArray<EqPacket *> *_queue;
    NSLock *_qlock;
    volatile NSInteger _buffered;
    volatile BOOL _stopped;
    BOOL _mute;
    BOOL _haveFormat, _haveCookie;
    void *_pendingCookie;
    UInt32 _pendingCookieSize;
    EqPacket *_held;                 // packet currently being read by the converter
    AudioStreamPacketDescription _curDesc;  // stable desc pointer for the converter
    dispatch_queue_t _pumpQ;
    NSURLSession *_session;
    NSURLSessionDataTask *_task;
    ExtAudioFileRef _capture;
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = [NSMutableArray array];
        _qlock = [[NSLock alloc] init];
        _pumpQ = dispatch_queue_create("eq.pump", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)isPlaying { return _player.isPlaying; }
- (void)setMute:(BOOL)mute { _mute = mute; }

- (void)openCaptureIfNeeded {
    if (!_captureFile.length) return;
    // Write a CAF containing the post‑EQ PCM (outputFormat). Created once the
    // format is known — see setupGraphAndConverter. For now just note the path.
}

- (void)setGains:(NSArray<NSNumber *> *)gains {
    if (!_eq) return;
    double g[kNumBands];
    memset(g, 0, sizeof(g));
    if ([gains isKindOfClass:[NSArray class]]) {
        NSUInteger n = MIN(gains.count, kNumBands);
        for (NSUInteger i = 0; i < n; i++) {
            id e = gains[i];
            double v = [e isKindOfClass:[NSNumber class]] ? [e doubleValue] : 0.0;
            if (v > 12.0) v = 12.0;
            if (v < -12.0) v = -12.0;
            g[i] = v;
        }
    }
    for (NSUInteger i = 0; i < _eq.bands.count && i < kNumBands; i++) {
        AVAudioUnitEQFilterParameters *p = _eq.bands[i];
        p.filterType = (i == 0) ? AVAudioUnitEQFilterTypeLowShelf
                       : (i == kNumBands - 1) ? AVAudioUnitEQFilterTypeHighShelf
                       : AVAudioUnitEQFilterTypeParametric;
        p.frequency = kBandCenters[i];
        p.bandwidth = 1.0;
        p.gain = g[i];
        p.bypass = NO;
    }
}

#pragma mark - start / stop

- (void)playURL:(NSURL *)url {
    OSStatus s = AudioFileStreamOpen((__bridge void *)self, propertyProc, packetsProc,
                                     kAudioFileAAC_ADTSType, &_streamID);
    if (s != noErr) { NSLog(@"[eq] AudioFileStreamOpen err=%d", (int)s); return; }

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.HTTPMaximumConnectionsPerHost = 1;
    _session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];
    _task = [_session dataTaskWithURL:url];
    [_task resume];
    NSLog(@"[eq] streaming %@", url);
}

- (void)stop {
    @synchronized(self) { _stopped = YES; }
    [_task cancel];
    _task = nil;
    [_session invalidateAndCancel];
    _session = nil;
    [_player stop];
    [_engine pause];
    @synchronized(self) {
        if (_converter) { AudioConverterDispose(_converter); _converter = NULL; }
        if (_streamID) { AudioFileStreamClose(_streamID); _streamID = NULL; }
        if (_capture) { ExtAudioFileDispose(_capture); _capture = NULL; }
        free(_pendingCookie); _pendingCookie = NULL; _pendingCookieSize = 0;
        [_queue removeAllObjects];
    }
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dt
       didReceiveData:(NSData *)data {
    @synchronized(self) {
        if (_stopped) return;
        static long _calls = 0, _bytes = 0;
        _calls++; _bytes += data.length;
        OSStatus s = AudioFileStreamParseBytes(_streamID, (UInt32)data.length, data.bytes, 0);
        if (s != noErr && s != kAudioFileStreamError_NotOptimized) {
            NSLog(@"[eq] ParseBytes err=%d (call#%ld totalBytes=%ld)", (int)s, _calls, _bytes);
        } else if (_calls % 10 == 0) {
            NSLog(@"[eq] recv call#%ld bytes=%ld q=%lu eng=%d ply=%d buf=%ld",
                  _calls, _bytes, (unsigned long)_queue.count,
                  (int)self.engine.isRunning, (int)self.player.isPlaying, (long)_buffered);
        }
    }
    [self pump];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    didCompleteWithError:(NSError *)err {
    if (err) NSLog(@"[eq] stream ended: %@", err);
}

#pragma mark - AudioFileStream callbacks (C → self)

static void propertyProc(void *userData, AudioFileStreamID streamID,
                         AudioFileStreamPropertyID prop, UInt32 *flags) {
    EqualizedStreamPlayer *me = (__bridge EqualizedStreamPlayer *)userData;
    if (prop == kAudioFileStreamProperty_DataFormat) {
        UInt32 size = sizeof(AudioStreamBasicDescription);
        AudioFileStreamGetProperty(streamID, prop, &size, &me->_inputFormat);
        me->_haveFormat = YES;
        [me maybeSetup];
    } else if (prop == kAudioFileStreamProperty_MagicCookieData) {
        UInt32 cookieSize = 0;
        AudioFileStreamGetPropertyInfo(streamID, prop, &cookieSize, NULL);
        if (cookieSize > 0) {
            free(me->_pendingCookie);
            me->_pendingCookie = malloc(cookieSize);
            AudioFileStreamGetProperty(streamID, prop, &cookieSize, me->_pendingCookie);
            me->_pendingCookieSize = cookieSize;
            me->_haveCookie = YES;
        }
        [me maybeSetup];
    }
}

// Create the converter/graph only once both the stream format and (for AAC)
// its magic cookie are known. The two arrive as separate property callbacks.
- (void)maybeSetup {
    @synchronized(self) {
        if (_formatKnown || _stopped || !_haveFormat) return;
        BOOL needsCookie = (_inputFormat.mFormatID == kAudioFormatMPEG4AAC
                            || _inputFormat.mFormatID == kAudioFormatMPEG4AAC_HE
                            || _inputFormat.mFormatID == kAudioFormatMPEG4AAC_HE_V2
                            || _inputFormat.mFormatID == kAudioFormatMPEG4AAC_ELD);
        if (needsCookie && !_haveCookie) return;  // wait for the cookie callback
        [self setupGraphAndConverter];
    }
}

static void packetsProc(void *userData, UInt32 numBytes, UInt32 numPackets,
                        const void *data, AudioStreamPacketDescription *packets) {
    EqualizedStreamPlayer *me = (__bridge EqualizedStreamPlayer *)userData;
    [me->_qlock lock];
    for (UInt32 i = 0; i < numPackets; i++) {
        EqPacket *p = [EqPacket new];
        const char *base = (const char *)data + packets[i].mStartOffset;
        p.data = [NSData dataWithBytes:base length:packets[i].mDataByteSize];
        AudioStreamPacketDescription d = packets[i];
        d.mStartOffset = 0;
        p.desc = d;
        [me->_queue addObject:p];
    }
    [me->_qlock unlock];
}

#pragma mark - graph + converter

- (void)setupGraphAndConverter {
    @synchronized(self) {
        if (_formatKnown || _stopped) return;

        _outputFormat = (AudioStreamBasicDescription){0};
        _outputFormat.mSampleRate = _inputFormat.mSampleRate > 0 ? _inputFormat.mSampleRate : 44100;
        _outputFormat.mFormatID = kAudioFormatLinearPCM;
        _outputFormat.mChannelsPerFrame = MAX(_inputFormat.mChannelsPerFrame, 1u);
        _outputFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;  // interleaved
        _outputFormat.mFramesPerPacket = 1;
        _outputFormat.mBytesPerFrame = _outputFormat.mChannelsPerFrame * 4;
        _outputFormat.mBytesPerPacket = _outputFormat.mBytesPerFrame;
        _outputFormat.mBitsPerChannel = 32;

        NSLog(@"[eq] input ASBD: id='%c%c%c%c' rate=%.0f ch=%u bps=%u fpp=%u bpp=%u flags=0x%x cookie=%uB",
              (char)(_inputFormat.mFormatID>>24),(char)(_inputFormat.mFormatID>>16),
              (char)(_inputFormat.mFormatID>>8),(char)_inputFormat.mFormatID,
              _inputFormat.mSampleRate, _inputFormat.mChannelsPerFrame, _inputFormat.mBitsPerChannel,
              _inputFormat.mFramesPerPacket, _inputFormat.mBytesPerPacket, _inputFormat.mFormatFlags,
              _pendingCookieSize);
        NSLog(@"[eq] output ASBD: rate=%.0f ch=%u bpf=%u bpp=%u flags=0x%x",
              _outputFormat.mSampleRate, _outputFormat.mChannelsPerFrame,
              _outputFormat.mBytesPerFrame, _outputFormat.mBytesPerPacket, _outputFormat.mFormatFlags);
        OSStatus s = AudioConverterNew(&_inputFormat, &_outputFormat, &_converter);
        if (s != noErr) {
            NSLog(@"[eq] AudioConverterNew err=%d (inFormat=%u)", (int)s, _inputFormat.mFormatID);
            return;
        }
        // (streaming gate added in pump: never feed the converter an empty input)
        if (_pendingCookie) {
            OSStatus cs = AudioConverterSetProperty(_converter, kAudioConverterDecompressionMagicCookie,
                                                    _pendingCookieSize, _pendingCookie);
            NSLog(@"[eq] setMagicCookie result=%d size=%u", (int)cs, _pendingCookieSize);
        }
        // The AAC decoder only emits interleaved PCM; AVAudioEngine needs
        // non-interleaved between nodes. So: converter -> interleaved scratch,
        // then deinterleave into a non-interleaved buffer for the graph.
        _convFmt = [[AVAudioFormat alloc] initWithStreamDescription:&_outputFormat];
        _outFmt = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:_outputFormat.mSampleRate
                                                                  channels:_outputFormat.mChannelsPerFrame];
        NSLog(@"[eq] convFmt interleave=%d  engineFmt interleave=%d",
              _convFmt.isInterleaved, _outFmt.isInterleaved);

        _engine = [[AVAudioEngine alloc] init];
        _player = [[AVAudioPlayerNode alloc] init];
        _eq = [[AVAudioUnitEQ alloc] initWithNumberOfBands:kNumBands];
        [_engine attachNode:_player];
        [_engine attachNode:_eq];
        [_engine connect:_player to:_eq format:_outFmt];
        [_engine connect:_eq to:_engine.mainMixerNode format:_outFmt];  // mainMixer auto-routes to outputNode
        NSLog(@"[eq] graph connected");

        // optional capture of post‑EQ PCM
        if (_captureFile.length) [self openCaptureWithFormat];

        NSError *e = nil;
        if (![_engine startAndReturnError:&e]) { NSLog(@"[eq] engine start: %@", e); return; }
        [_player play];

        _formatKnown = YES;
        [self setGains:nil];  // flat layout
        NSLog(@"[eq] ready: %.0f Hz %u ch (decoder for inFormat=%u, cookie=%uB)",
              _outputFormat.mSampleRate, _outputFormat.mChannelsPerFrame,
              _inputFormat.mFormatID, _pendingCookieSize);
    }
    [self pump];
}

- (void)openCaptureWithFormat {
    NSURL *url = [NSURL fileURLWithPath:_captureFile];
    AudioStreamBasicDescription f = _outputFormat;
    OSStatus s = ExtAudioFileCreateWithURL((__bridge CFURLRef)url, kAudioFileCAFType,
                                           &f, NULL, kAudioFileFlags_EraseFile, &_capture);
    if (s != noErr) { NSLog(@"[eq] capture create err=%d", (int)s); return; }
    ExtAudioFileSetProperty(_capture, kExtAudioFileProperty_ClientDataFormat, sizeof(f), &f);
    ExtAudioFileWriteAsync(_capture, 0, NULL);  // prime async writes
}

#pragma mark - decode + schedule

static OSStatus converterInputProc(AudioConverterRef conv, UInt32 *ioNumPackets,
                                   AudioBufferList *ioData,
                                   AudioStreamPacketDescription **outDesc,
                                   void *userData) {
    EqualizedStreamPlayer *me = (__bridge EqualizedStreamPlayer *)userData;
    { static int _c = 0; _c++; if (_c <= 3 || _c % 50 == 0) NSLog(@"[eq] inputProc#%d q=%lu", _c, (unsigned long)me->_queue.count); }
    [me->_qlock lock];
    EqPacket *p = (me->_queue.count > 0) ? me->_queue[0] : nil;
    if (p) [me->_queue removeObjectAtIndex:0];
    [me->_qlock unlock];

    if (!p) {
        *ioNumPackets = 0;
        return noErr;  // no data right now; caller will produce whatever it has so far
    }
    me->_curDesc = p.desc;
    me->_curDesc.mStartOffset = 0;

    *ioNumPackets = 1;
    ioData->mNumberBuffers = 1;
    ioData->mBuffers[0].mData = (void *)p.data.bytes;
    ioData->mBuffers[0].mDataByteSize = (UInt32)p.data.length;
    if (outDesc) *outDesc = &me->_curDesc;
    {
        static int _inpLog = 0;
        if (_inpLog < 3) {
            _inpLog++;
            NSLog(@"[eq] inputProc#%d bytes=%u desc{off=%llu dbsize=%llu vfip=%u}",
                  _inpLog, (UInt32)p.data.length, (unsigned long long)p.desc.mStartOffset,
                  (unsigned long long)p.desc.mDataByteSize, p.desc.mVariableFramesInPacket);
        }
    }
    return noErr;
}

- (void)pump {
    dispatch_async(_pumpQ, ^{
        @synchronized(self) {
            if (self->_stopped || !_formatKnown) return;
            while (self->_buffered < (NSInteger)kMaxBuffered) @try {
                if (self->_queue.count < kPacketsPerBuffer) break;  // wait for a full buffer's worth (never starve the converter → avoids EOS)
                UInt32 cap = kPacketsPerBuffer * MAX(self->_inputFormat.mFramesPerPacket, 1u);  // frames
                UInt32 bytes = cap * self->_outputFormat.mBytesPerFrame;
                float *idata = (float *)malloc(bytes);  // interleaved decode scratch (AAC → interleaved)
                if (!idata) break;
                AudioBufferList rawABL;
                rawABL.mNumberBuffers = 1;
                rawABL.mBuffers[0].mNumberChannels = self->_outputFormat.mChannelsPerFrame;
                rawABL.mBuffers[0].mDataByteSize = bytes;
                rawABL.mBuffers[0].mData = idata;
                UInt32 numPackets = cap;  // ioOutputDataPacketSize == output frames (PCM fpp=1)
                OSStatus err = AudioConverterFillComplexBuffer(self->_converter, converterInputProc,
                                                               (__bridge void *)self, &numPackets, &rawABL, NULL);
                { static int _f = 0; if (_f < 5) { _f++; NSLog(@"[eq] fill err=%d numPackets=%u", (int)err, (unsigned)numPackets); } }
                if (numPackets == 0) { free(idata); break; }  // truly starved; ignore non-zero err if we got partial output
                // deinterleave into a non-interleaved buffer for AVAudioEngine
                AVAudioPCMBuffer *pcm = [[AVAudioPCMBuffer alloc] initWithPCMFormat:self->_outFmt frameCapacity:numPackets];
                if (!pcm) { free(idata); break; }
                AVAudioFrameCount fl = MIN(numPackets, pcm.frameCapacity);
                pcm.frameLength = fl;
                UInt32 ch = self->_outFmt.channelCount;
                for (UInt32 c = 0; c < ch; c++) {
                    float *dst = pcm.floatChannelData[c];
                    for (UInt32 f = 0; f < fl; f++) dst[f] = idata[f * ch + c];
                }
                free(idata);
                AudioBufferList *abl = (AudioBufferList *)pcm.audioBufferList;
                if (self->_mute) {
                    for (UInt32 b = 0; b < abl->mNumberBuffers; b++)
                        memset(abl->mBuffers[b].mData, 0, abl->mBuffers[b].mDataByteSize);
                }
                if (self->_capture) ExtAudioFileWriteAsync(self->_capture, pcm.frameLength, abl);

                self->_buffered++;
                __weak typeof(self) ws = self;
                [self->_player scheduleBuffer:pcm completionHandler:^{
                    __strong typeof(ws) s = ws;
                    { static int _cmp = 0; _cmp++; if (_cmp <= 3 || _cmp % 50 == 0) NSLog(@"[eq] buffer done #%d", _cmp); }
                    if (!s) return;
                    @synchronized(s) { s->_buffered--; }
                    [s pump];
                }];
                if (!self->_player.isPlaying) [self->_player play];  // recover from underrun
                if (err != noErr) {
                    NSLog(@"[eq] convert err=%d", (int)err);
                    break;
                }
            } @catch(NSException *ex) {
                NSLog(@"[eq] pump EXC %@: %@", ex.name, ex.reason);
                break;
            }
        }
    });
}

- (void)dealloc {
    [self stop];
}

@end
