#import "./include/just_audio/UriAudioSource.h"
#import "./include/just_audio/IndexedAudioSource.h"
#import "./include/just_audio/IndexedPlayerItem.h"
#import "./include/just_audio/LoadControl.h"
#import <AVFoundation/AVFoundation.h>

/// FairPlay Streaming license exchange via AVContentKeySession.
@interface _JustAudioFairPlayDelegate : NSObject <AVContentKeySessionDelegate>
@property (nonatomic, copy) NSString *licenseUrl;
@property (nonatomic, copy) NSString *fairplayCertUrl;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *licenseHeaders;
@end

@implementation _JustAudioFairPlayDelegate

/// Content ID for SPC: strip `skd://` (Apple FPS convention).
/// Using the full `skd://…` absoluteString breaks license exchange.
- (nullable NSData *)_contentIdDataFromKeyRequest:(AVContentKeyRequest *)keyRequest {
    id identifier = keyRequest.identifier;
    NSString *raw = nil;
    if ([identifier isKindOfClass:[NSURL class]]) {
        NSURL *url = (NSURL *)identifier;
        // Prefer host when URI is skd://<contentId>
        if (url.host.length > 0) {
            raw = url.host;
        } else {
            raw = url.absoluteString;
        }
    } else if ([identifier isKindOfClass:[NSString class]]) {
        raw = (NSString *)identifier;
    } else if ([identifier isKindOfClass:[NSData class]]) {
        return (NSData *)identifier;
    }
    if (raw.length == 0) return nil;

    NSString *stripped = raw;
    if ([stripped.lowercaseString hasPrefix:@"skd://"]) {
        stripped = [stripped substringFromIndex:6];
    }
    NSString *decoded = [stripped stringByRemovingPercentEncoding] ?: stripped;
    if (decoded.length == 0) return nil;
    return [decoded dataUsingEncoding:NSUTF8StringEncoding];
}

- (void)_postLicenseWithSpc:(NSData *)spcData
                 keyRequest:(AVContentKeyRequest *)keyRequest API_AVAILABLE(ios(10.3), macos(10.12.4)) {
    NSString *spcB64 = [spcData base64EncodedStringWithOptions:0];
    // Many FairPlay license servers expect application/x-www-form-urlencoded
    // with an encodeURIComponent-style `spc=` body.
    NSCharacterSet *allowed = [NSCharacterSet
        characterSetWithCharactersInString:
            @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    NSString *encoded = [spcB64 stringByAddingPercentEncodingWithAllowedCharacters:allowed]
        ?: spcB64;
    NSString *bodyString = [NSString stringWithFormat:@"spc=%@", encoded];
    NSData *body = [bodyString dataUsingEncoding:NSUTF8StringEncoding];

    NSURL *licenseURL = [NSURL URLWithString:self.licenseUrl];
    if (!licenseURL) {
        [keyRequest processContentKeyResponseError:
            [NSError errorWithDomain:@"just_audio.drm" code:5
                            userInfo:@{NSLocalizedDescriptionKey: @"Invalid FairPlay license URL"}]];
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:licenseURL];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    for (NSString *key in self.licenseHeaders) {
        id value = self.licenseHeaders[key];
        if ([value isKindOfClass:[NSString class]]) {
            [req setValue:(NSString *)value forHTTPHeaderField:key];
        }
    }
    req.HTTPBody = body;

    [[[NSURLSession sharedSession] dataTaskWithRequest:req
                                     completionHandler:^(NSData *ckcData, NSURLResponse *licResponse, NSError *licError) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)licResponse;
        NSInteger status = [http isKindOfClass:[NSHTTPURLResponse class]] ? http.statusCode : 0;
        if (licError || ckcData.length == 0 || status < 200 || status >= 300) {
            NSString *msg = [NSString stringWithFormat:
                @"FairPlay license failed (HTTP %ld, %lu bytes)",
                (long)status, (unsigned long)ckcData.length];
            NSLog(@"[just_audio DRM] %@", msg);
            [keyRequest processContentKeyResponseError:
                licError ?: [NSError errorWithDomain:@"just_audio.drm" code:4
                                          userInfo:@{NSLocalizedDescriptionKey: msg}]];
            return;
        }
        // Some license servers return HTTP 200 + JSON error — reject before CKC parse.
        NSString *asText = [[NSString alloc] initWithData:ckcData encoding:NSUTF8StringEncoding];
        if (asText != nil) {
            NSString *trimmed = [asText stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([trimmed hasPrefix:@"{"]) {
                NSLog(@"[just_audio DRM] license JSON error: %@", trimmed);
                [keyRequest processContentKeyResponseError:
                    [NSError errorWithDomain:@"just_audio.drm" code:8
                                    userInfo:@{NSLocalizedDescriptionKey: trimmed}]];
                return;
            }
        }
        NSData *rawCkc = [self _decodeIfBase64:ckcData] ?: ckcData;
        if (rawCkc.length == 0) {
            [keyRequest processContentKeyResponseError:
                [NSError errorWithDomain:@"just_audio.drm" code:9
                                userInfo:@{NSLocalizedDescriptionKey: @"Empty FairPlay CKC"}]];
            return;
        }
        NSLog(@"[just_audio DRM] CKC ok (%lu bytes)", (unsigned long)rawCkc.length);
        AVContentKeyResponse *keyResponse =
            [AVContentKeyResponse contentKeyResponseWithFairPlayStreamingKeyResponseData:rawCkc];
        [keyRequest processContentKeyResponse:keyResponse];
    }] resume];
}

- (void)contentKeySession:(AVContentKeySession *)session
    didProvideContentKeyRequest:(AVContentKeyRequest *)keyRequest API_AVAILABLE(ios(10.3), macos(10.12.4)) {
    NSURL *certURL = [NSURL URLWithString:_fairplayCertUrl];
    if (!certURL) {
        [keyRequest processContentKeyResponseError:
            [NSError errorWithDomain:@"just_audio.drm" code:1
                            userInfo:@{NSLocalizedDescriptionKey: @"Invalid FairPlay cert URL"}]];
        return;
    }

    NSData *contentId = [self _contentIdDataFromKeyRequest:keyRequest];
    if (contentId.length == 0) {
        NSLog(@"[just_audio DRM] missing FairPlay content id from keyRequest.identifier=%@",
              keyRequest.identifier);
        [keyRequest processContentKeyResponseError:
            [NSError errorWithDomain:@"just_audio.drm" code:6
                            userInfo:@{NSLocalizedDescriptionKey: @"Missing FairPlay content id"}]];
        return;
    }
    NSLog(@"[just_audio DRM] contentId=%@",
          [[NSString alloc] initWithData:contentId encoding:NSUTF8StringEncoding]);

    [[[NSURLSession sharedSession] dataTaskWithURL:certURL
                                 completionHandler:^(NSData *certData, NSURLResponse *response, NSError *error) {
        if (error || certData.length == 0) {
            [keyRequest processContentKeyResponseError:
                error ?: [NSError errorWithDomain:@"just_audio.drm" code:2
                                          userInfo:@{NSLocalizedDescriptionKey: @"FairPlay cert fetch failed"}]];
            return;
        }

        // Certificate endpoint may return raw DER or base64 text.
        // Apple requires raw certificate bytes as appIdentifier.
        NSData *rawCert = [self _fpsCertificateBytes:certData];
        if (rawCert.length == 0) {
            NSString *preview = [[NSString alloc] initWithData:certData encoding:NSUTF8StringEncoding] ?: @"";
            if (preview.length > 240) preview = [preview substringToIndex:240];
            // Some servers return HTTP 200 + JSON when the cert is unavailable.
            NSString *msg = [preview hasPrefix:@"{"]
                ? [NSString stringWithFormat:
                    @"FairPlay cert unavailable: %@", preview]
                : [NSString stringWithFormat:
                    @"Invalid FairPlay certificate payload: %@", preview];
            NSLog(@"[just_audio DRM] %@", msg);
            [keyRequest processContentKeyResponseError:
                [NSError errorWithDomain:@"just_audio.drm" code:7
                                userInfo:@{NSLocalizedDescriptionKey: msg}]];
            return;
        }
        NSLog(@"[just_audio DRM] FPS cert decoded (%lu bytes)", (unsigned long)rawCert.length);

        [keyRequest makeStreamingContentKeyRequestDataForApp:rawCert
                                           contentIdentifier:contentId
                                                     options:nil
                                           completionHandler:^(NSData * _Nullable spcData, NSError * _Nullable spcError) {
            if (spcError || spcData.length == 0) {
                NSLog(@"[just_audio DRM] SPC generation failed: %@", spcError);
                [keyRequest processContentKeyResponseError:
                    spcError ?: [NSError errorWithDomain:@"just_audio.drm" code:3
                                              userInfo:@{NSLocalizedDescriptionKey: @"SPC generation failed"}]];
                return;
            }
            [self _postLicenseWithSpc:spcData keyRequest:keyRequest];
        }];
    }] resume];
}

- (void)contentKeySession:(AVContentKeySession *)session
    didProvidePersistableContentKeyRequest:(AVPersistableContentKeyRequest *)keyRequest API_AVAILABLE(ios(10.3), macos(10.15)) {
    [self contentKeySession:session didProvideContentKeyRequest:keyRequest];
}

/// FairPlay cert endpoint may return base64 text (or JSON error with HTTP 200).
- (nullable NSData *)_fpsCertificateBytes:(NSData *)body {
    if (body.length == 0) return nil;
    // Already looks like DER (SEQUENCE tag 0x30) — use as-is.
    const uint8_t *bytes = body.bytes;
    if (bytes[0] == 0x30) return body;

    NSString *text = [[[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) return nil;
    if ([text hasPrefix:@"{"]) {
        // JSON error body (still HTTP 200).
        return nil;
    }
    NSData *decoded = [[NSData alloc] initWithBase64EncodedString:text
                                                          options:NSDataBase64DecodingIgnoreUnknownCharacters];
    return decoded.length > 0 ? decoded : nil;
}

- (nullable NSData *)_decodeIfBase64:(NSData *)data {
    if (data.length == 0) return nil;
    // License failures may also return HTTP 200 + JSON — don't treat as CKC.
    NSString *asText = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (asText != nil) {
        NSString *trimmed = [asText stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([trimmed hasPrefix:@"{"]) {
            NSLog(@"[just_audio DRM] license JSON error: %@", trimmed);
            return nil;
        }
    }
    const uint8_t *bytes = data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) {
        uint8_t b = bytes[i];
        BOOL ok = (b >= 'A' && b <= 'Z') || (b >= 'a' && b <= 'z') ||
                  (b >= '0' && b <= '9') || b == '+' || b == '/' || b == '=' ||
                  b == '\n' || b == '\r';
        if (!ok) return nil;
    }
    NSString *text = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) return nil;
    return [[NSData alloc] initWithBase64EncodedString:text options:NSDataBase64DecodingIgnoreUnknownCharacters];
}

@end

@implementation UriAudioSource {
    NSString *_uri;
    IndexedPlayerItem *_playerItem;
    IndexedPlayerItem *_playerItem2;
    LoadControl *_loadControl;
    NSMutableDictionary *_headers;
    NSDictionary *_options;
    NSDictionary *_drm;
    AVContentKeySession *_contentKeySession;
    _JustAudioFairPlayDelegate *_fairPlayDelegate;
}

- (instancetype)initWithId:(NSString *)sid uri:(NSString *)uri loadControl:(LoadControl *)loadControl headers:(NSDictionary *)headers options:(NSDictionary *)options {
    return [self initWithId:sid uri:uri loadControl:loadControl headers:headers options:options drm:nil];
}

- (instancetype)initWithId:(NSString *)sid
                       uri:(NSString *)uri
               loadControl:(LoadControl *)loadControl
                   headers:(NSDictionary *)headers
                   options:(NSDictionary *)options
                       drm:(NSDictionary *)drm {
    self = [super initWithId:sid];
    NSAssert(self, @"super init cannot be nil");
    _uri = uri;
    _loadControl = loadControl;
    _headers = headers != (id)[NSNull null] ? [headers mutableCopy] : nil;
    _options = options != (id)[NSNull null] ? options : nil;
    _drm = drm != (id)[NSNull null] ? drm : nil;
    _playerItem = [self createPlayerItem:uri];
    _playerItem2 = nil;
    return self;
}

- (NSString *)uri {
    return _uri;
}

- (void)_attachFairPlayIfNeeded:(AVURLAsset *)asset {
    if (!_drm) return;
    NSString *licenseUrl = _drm[@"licenseUrl"];
    NSString *certUrl = _drm[@"fairplayCertUrl"];
    if (![licenseUrl isKindOfClass:[NSString class]] || licenseUrl.length == 0) {
        NSLog(@"[just_audio DRM] missing licenseUrl — FairPlay not attached");
        return;
    }
    if (![certUrl isKindOfClass:[NSString class]] || certUrl.length == 0) {
        // Without a cert, AVPlayer fails encrypted HLS with opaque -11800.
        NSLog(@"[just_audio DRM] missing fairplayCertUrl — FairPlay not attached");
        return;
    }
    if (@available(iOS 10.3, macOS 10.12.4, *)) {
        _fairPlayDelegate = [[_JustAudioFairPlayDelegate alloc] init];
        _fairPlayDelegate.licenseUrl = licenseUrl;
        _fairPlayDelegate.fairplayCertUrl = certUrl;
        NSDictionary *headers = _drm[@"licenseHeaders"];
        if ([headers isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary<NSString *, NSString *> *stringHeaders =
                [NSMutableDictionary dictionary];
            [headers enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                if ([key isKindOfClass:[NSString class]] &&
                    [obj isKindOfClass:[NSString class]]) {
                    stringHeaders[(NSString *)key] = (NSString *)obj;
                }
            }];
            _fairPlayDelegate.licenseHeaders = stringHeaders;
        } else {
            _fairPlayDelegate.licenseHeaders = @{};
        }
        _contentKeySession =
            [AVContentKeySession contentKeySessionWithKeySystem:AVContentKeySystemFairPlayStreaming];
        [_contentKeySession setDelegate:_fairPlayDelegate queue:dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)];
        [_contentKeySession addContentKeyRecipient:asset];
        NSLog(@"[just_audio DRM] FairPlay ContentKeySession attached for %@", asset.URL);
    }
}

- (IndexedPlayerItem *)createPlayerItem:(NSString *)uri {
    IndexedPlayerItem *item;
    NSMutableDictionary *assetOptions = [[NSMutableDictionary alloc] init];

    if (_options != (id)[NSNull null] && _options != nil) {
        NSDictionary *darwinOptions = _options[@"darwinAssetOptions"];
        if (darwinOptions != (id)[NSNull null] && darwinOptions != nil) {
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

        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL URLWithString:uri] options:assetOptions];
        [self _attachFairPlayIfNeeded:asset];
        item = [[IndexedPlayerItem alloc] initWithAsset:asset];
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
}

- (void)preparePlayerItem2 {
    if (!_playerItem2) {
        _playerItem2 = [self createPlayerItem:_uri];
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
