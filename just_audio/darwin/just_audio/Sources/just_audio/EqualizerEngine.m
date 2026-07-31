#import "./include/just_audio/EqualizerEngine.h"

#import <MediaToolbox/MTAudioProcessingTap.h>
#import <os/lock.h>

NS_ASSUME_NONNULL_BEGIN

/// Private methods used by the C tap callbacks (defined above @implementation).
@interface EqualizerEngine ()
- (void)snapshotGains:(double *)out armed:(BOOL *)armedOut;
@end

/// Canonical 10-band ISO centres (Hz). MUST match `canonicalCentresHz` in
/// lib/models/equalizer_preset.dart.
static const double kEqCentres[] = {
    31.25, 62.5, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0,
};
static const NSUInteger kEqSections = 10;
static const double kEqQ = 1.41;  // ~1-octave graphic-EQ Q (sqrt 2).

/// One normalised biquad section: y[n] = b0*x + b1*x1 + b2*x2 - a1*y1 - a2*y2
/// (RBJ peaking-EQ form). Stored as float; the cascade runs in float.
typedef struct {
    float b0, b1, b2, a1, a2;
} EqCoeff;

/// Per-tap real-time state. Allocated in `prepare` (format known then), freed
/// in `unprepare`/`finalize`. `state` layout: channel-major, then section, then
/// [s1, s2] (Transposed Direct Form II registers).
typedef struct {
    double sampleRate;
    UInt32 channels;
    float *state;                  // channels * kEqSections * 2
    double gainsSnapshot[kEqSections];  // last-applied gains (force recompute when dirty)
    EqCoeff coeffs[kEqSections];
    BOOL dirty;
} EqTapState;

// MARK: - DSP

/// Apply the cascaded biquad chain in-place to one channel. Transposed Direct
/// Form II (numerically stable for audio, minimal state). No allocation.
static void EqApplyChain(const EqCoeff *coeffs,
                         NSUInteger sections,
                         float *state,
                         float *samples,
                         UInt32 count) {
    for (UInt32 i = 0; i < count; i++) {
        float x = samples[i];
        for (NSUInteger s = 0; s < sections; s++) {
            float s1 = state[2 * s];
            float s2 = state[2 * s + 1];
            float y = coeffs[s].b0 * x + s1;
            state[2 * s] = coeffs[s].b1 * x - coeffs[s].a1 * y + s2;
            state[2 * s + 1] = coeffs[s].b2 * x - coeffs[s].a2 * y;
            x = y;
        }
        samples[i] = x;
    }
}

/// Compute normalised RBJ peaking-EQ coefficients for each band from the gain
/// vector (dB) and sample rate. A flat band (|dB| < 0.001) becomes an identity
/// section (bypass within the chain). Real-time-safe: no allocation.
static void EqComputeCoeffs(const double gains[10],
                            double sampleRate,
                            EqCoeff outCoeffs[10]) {
    for (NSUInteger i = 0; i < kEqSections; i++) {
        double dB = gains[i];
        if (fabs(dB) < 0.001 || sampleRate <= 0.0) {
            outCoeffs[i].b0 = 1.0f;
            outCoeffs[i].b1 = 0.0f;
            outCoeffs[i].b2 = 0.0f;
            outCoeffs[i].a1 = 0.0f;
            outCoeffs[i].a2 = 0.0f;
            continue;
        }
        double A = pow(10.0, dB / 40.0);
        double w0 = 2.0 * M_PI * kEqCentres[i] / sampleRate;
        double cosw0 = cos(w0);
        double sinw0 = sin(w0);
        double alpha = sinw0 / (2.0 * kEqQ);
        double b0 = 1.0 + alpha * A;
        double b1 = -2.0 * cosw0;
        double b2 = 1.0 - alpha * A;
        double a0 = 1.0 + alpha / A;
        double a1 = -2.0 * cosw0;
        double a2 = 1.0 - alpha / A;
        outCoeffs[i].b0 = (float)(b0 / a0);
        outCoeffs[i].b1 = (float)(b1 / a0);
        outCoeffs[i].b2 = (float)(b2 / a0);
        outCoeffs[i].a1 = (float)(a1 / a0);
        outCoeffs[i].a2 = (float)(a2 / a0);
    }
}

// MARK: - MTAudioProcessingTap callbacks

static void EqTapInitCallback(void *clientInfo, void **tapStorageOut) {
    *tapStorageOut = NULL;
}

static void EqTapPrepareCallback(void *tapStorage,
                                 CMItemCount maxFrames,
                                 const AudioStreamBasicDescription *processingFormat,
                                 void *clientInfo) {
    EqTapState *st = (EqTapState *)tapStorage;
    if (!st) {
        st = (EqTapState *)calloc(1, sizeof(EqTapState));
    }
    if (processingFormat) {
        st->sampleRate = processingFormat->mSampleRate;
        st->channels = processingFormat->mChannelsPerFrame;
    }
    NSUInteger floats = (NSUInteger)st->channels * kEqSections * 2u;
    if (floats > 0 && st->state == NULL) {
        st->state = (float *)calloc(floats, sizeof(float));
    }
    st->dirty = YES;  // force a coefficient recompute on first process
    NSLog(@"[EqualizerEngine] prepare: %.0f Hz, %u ch, %lld maxFrames",
          st->sampleRate, (unsigned int)st->channels, (long long)maxFrames);
}

static void EqTapUnprepareCallback(void *tapStorage, void *clientInfo) {
    EqTapState *st = (EqTapState *)tapStorage;
    if (st && st->state) {
        free(st->state);
        st->state = NULL;
    }
}

static void EqTapFinalizeCallback(void *tapStorage, void *clientInfo) {
    EqTapState *st = (EqTapState *)tapStorage;
    if (st) {
        if (st->state) free(st->state);
        free(st);
    }
    // Balance the CFBridgingRetain(self) done at tap creation. Each tap holds
    // one retain on the engine; releasing here keeps it alive exactly as long
    // as any tap references it.
    if (clientInfo) {
        CFBridgingRelease(clientInfo);
    }
}

static void EqTapProcessCallback(void *tapStorage,
                                 CMItemCount numberFrames,
                                 MTAudioProcessingTapFlags flags,
                                 AudioBufferList *bufferListInOut,
                                 void *clientInfo) {
    EqTapState *st = (EqTapState *)tapStorage;
    EqualizerEngine *engine = (__bridge EqualizerEngine *)clientInfo;
    if (!st || !engine || numberFrames == 0) return;

    BOOL armed = NO;
    double gains[kEqSections];
    [engine snapshotGains:gains armed:&armed];
    if (!armed) return;  // disarmed (flat): leave the buffer untouched (bypass)

    // Recompute coefficients only when the gain vector changed since last call.
    if (st->dirty || memcmp(gains, st->gainsSnapshot, sizeof(gains)) != 0) {
        EqComputeCoeffs(gains, st->sampleRate, st->coeffs);
        memcpy(st->gainsSnapshot, gains, sizeof(gains));
        st->dirty = NO;
    }

    // Non-interleaved Float32: one AudioBuffer per channel (mNumberBuffers ==
    // channels). Interleaved (mNumberBuffers == 1) is bypassed for safety.
    if (bufferListInOut->mNumberBuffers != st->channels) {
        return;
    }
    for (UInt32 b = 0; b < bufferListInOut->mNumberBuffers; b++) {
        AudioBuffer *buf = &bufferListInOut->mBuffers[b];
        if (!buf->mData || buf->mDataByteSize == 0) continue;
        UInt32 n = (UInt32)(buf->mDataByteSize / sizeof(float));
        EqApplyChain(st->coeffs, kEqSections, st->state + b * kEqSections * 2u,
                     (float *)buf->mData, n);
    }
}

// MARK: - EqualizerEngine

@implementation EqualizerEngine {
    double _gains[kEqSections];
    BOOL _armed;
    os_unfair_lock _lock;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        memset(_gains, 0, sizeof(_gains));
        _armed = NO;
        _lock = OS_UNFAIR_LOCK_INIT;
    }
    return self;
}

- (BOOL)armed {
    os_unfair_lock_lock(&_lock);
    BOOL value = _armed;
    os_unfair_lock_unlock(&_lock);
    return value;
}

- (void)setGains:(NSArray<NSNumber *> *)gains {
    double g[kEqSections];
    memset(g, 0, sizeof(g));
    BOOL flat = YES;
    NSUInteger n = gains.count < kEqSections ? gains.count : kEqSections;
    for (NSUInteger i = 0; i < n; i++) {
        double v = [gains[i] doubleValue];
        if (v > 12.0) v = 12.0;
        if (v < -12.0) v = -12.0;
        g[i] = v;
        if (fabs(v) > 0.001) flat = NO;
    }
    os_unfair_lock_lock(&_lock);
    memcpy(_gains, g, sizeof(g));
    _armed = !flat;
    os_unfair_lock_unlock(&_lock);
}

/// Real-time-safe snapshot of the current gain vector + armed flag. Called
/// from the tap's process callback (the audio render thread). Holds the lock
/// only long enough to copy 10 doubles + a bool.
- (void)snapshotGains:(double[kEqSections])out armed:(BOOL *)armedOut {
    os_unfair_lock_lock(&_lock);
    memcpy(out, _gains, sizeof(double) * kEqSections);
    *armedOut = _armed;
    os_unfair_lock_unlock(&_lock);
}

- (MTAudioProcessingTapRef _Nullable)createTap {
    MTAudioProcessingTapCallbacks callbacks = {
        .version = kMTAudioProcessingTapCallbacksVersion_0,
        .init = EqTapInitCallback,
        .prepare = EqTapPrepareCallback,
        .unprepare = EqTapUnprepareCallback,
        .process = EqTapProcessCallback,
        .finalize = EqTapFinalizeCallback,
    };
    void *clientInfo = (void *)CFBridgingRetain(self);  // +1, balanced in finalize
    MTAudioProcessingTapRef tap = NULL;
    OSStatus status = MTAudioProcessingTapCreate(
        kCFAllocatorDefault, &callbacks,
        kMTAudioProcessingTapCreationFlag_PostEffects, &tap);
    if (status != noErr || !tap) {
        NSLog(@"[EqualizerEngine] MTAudioProcessingTapCreate failed: %d", (int)status);
        CFBridgingRelease(clientInfo);  // finalize won't run; balance now
        return NULL;
    }
    return tap;
}

- (void)installTapsForAssetTracks:(NSArray<AVAssetTrack *> *)tracks
                           onItem:(AVPlayerItem *)item {
    if (!item || tracks.count == 0) return;
    NSMutableArray<AVMutableAudioMixInputParameters *> *params =
        [NSMutableArray arrayWithCapacity:tracks.count];
    for (AVAssetTrack *track in tracks) {
        MTAudioProcessingTapRef tap = [self createTap];
        if (!tap) continue;
        AVMutableAudioMixInputParameters *p =
            [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];
        [p setAudioTapProcessor:tap];
        [params addObject:p];
        CFRelease(tap);  // setAudioTapProcessor: retained it
    }
    if (params.count == 0) return;
    AVMutableAudioMix *mix = [AVMutableAudioMix audioMix];
    mix.inputParameters = params;
    item.audioMix = mix;
    NSLog(@"[EqualizerEngine] tap installed on %lu audio track(s)",
          (unsigned long)params.count);
}

/// Async-load audio tracks from the asset when `item.tracks` is empty — the
/// common HLS case, which doesn't expose tracks synchronously at readyToPlay.
- (void)loadAssetAudioTracksForItem:(AVPlayerItem *)item {
    AVAsset *asset = item.asset;
    __weak typeof(self) weakSelf = self;
    if (@available(iOS 16.0, macOS 13.0, *)) {
        [asset loadTracksWithMediaType:AVMediaTypeAudio
                     completionHandler:^(NSArray<AVAssetTrack *> *_Nullable tracks,
                                         NSError *_Nullable error) {
                         if (error || tracks.count == 0) {
                             NSLog(@"[EqualizerEngine] asset audio tracks empty/failed (%@) "
                                   @"— tap not installed (HLS may not expose tracks)", error);
                             return;
                         }
                         dispatch_async(dispatch_get_main_queue(), ^{
                             [weakSelf installTapsForAssetTracks:tracks onItem:item];
                         });
                     }];
    } else {
        NSString *key = @"tracks";
        [asset loadValuesAsynchronouslyForKeys:@[ key ] completionHandler:^{
            NSError *error = nil;
            AVKeyValueStatus status = [asset statusOfValueForKey:key error:&error];
            if (status != AVKeyValueStatusLoaded) {
                NSLog(@"[EqualizerEngine] asset tracks load status %ld (%@)",
                      (long)status, error);
                return;
            }
            NSArray<AVAssetTrack *> *tracks =
                [asset tracksWithMediaType:AVMediaTypeAudio];
            if (tracks.count == 0) {
                NSLog(@"[EqualizerEngine] asset has no audio tracks — tap not installed");
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf installTapsForAssetTracks:tracks onItem:item];
            });
        }];
    }
}

- (void)attachToPlayerItem:(AVPlayerItem *)item {
    if (!item) return;
    if (!self.armed) return;

    NSMutableArray<AVAssetTrack *> *audioTracks = [NSMutableArray array];
    for (AVPlayerItemTrack *playerTrack in item.tracks) {
        AVAssetTrack *assetTrack = playerTrack.assetTrack;
        if (assetTrack && assetTrack.mediaType == AVMediaTypeAudio) {
            [audioTracks addObject:assetTrack];
        }
    }
    if (audioTracks.count > 0) {
        [self installTapsForAssetTracks:audioTracks onItem:item];
    } else {
        [self loadAssetAudioTracksForItem:item];
    }
}

@end

NS_ASSUME_NONNULL_END
