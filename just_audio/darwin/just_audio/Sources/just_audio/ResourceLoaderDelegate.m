#import "./include/just_audio/ResourceLoaderDelegate.h"
#include <TargetConditionals.h>

#if __has_include(<UniformTypeIdentifiers/UniformTypeIdentifiers.h>)
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#endif

#if TARGET_OS_IPHONE
#import <MobileCoreServices/MobileCoreServices.h>
#else
#import <CoreServices/CoreServices.h>
#endif

static NSString *const kCustomSchemePrefix = @"just-audio-";

@implementation ResourceLoaderDelegate {
    NSString *_originalURLString;
    NSDictionary *_headers;
    NSURLSession *_session;
    NSMutableArray<NSURLSessionDataTask *> *_pendingTasks;
}

+ (NSString *)customSchemePrefix {
    return kCustomSchemePrefix;
}

+ (NSString *)interceptedURLString:(NSString *)urlString {
    if ([urlString hasPrefix:@"https://"]) {
        return [NSString stringWithFormat:@"%@https://%@", kCustomSchemePrefix, [urlString substringFromIndex:8]];
    } else if ([urlString hasPrefix:@"http://"]) {
        return [NSString stringWithFormat:@"%@http://%@", kCustomSchemePrefix, [urlString substringFromIndex:7]];
    }
    return urlString;
}

+ (BOOL)isInterceptedURLString:(NSString *)urlString {
    return [urlString hasPrefix:kCustomSchemePrefix];
}

/// Restores the original HTTP(S) URL from a custom-scheme URL.
+ (NSString *)restoreURLString:(NSString *)interceptedURLString {
    if ([interceptedURLString hasPrefix:[NSString stringWithFormat:@"%@https://", kCustomSchemePrefix]]) {
        return [NSString stringWithFormat:@"https://%@",
                [interceptedURLString substringFromIndex:kCustomSchemePrefix.length + 8]];
    } else if ([interceptedURLString hasPrefix:[NSString stringWithFormat:@"%@http://", kCustomSchemePrefix]]) {
        return [NSString stringWithFormat:@"http://%@",
                [interceptedURLString substringFromIndex:kCustomSchemePrefix.length + 7]];
    }
    return interceptedURLString;
}

- (instancetype)initWithOriginalURLString:(NSString *)originalURLString headers:(NSDictionary *)headers {
    self = [super init];
    if (self) {
        _originalURLString = [originalURLString copy];
        _headers = headers;
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        _session = [NSURLSession sessionWithConfiguration:config];
        _pendingTasks = [NSMutableArray array];
    }
    return self;
}

- (NSString *)originalURLString {
    return _originalURLString;
}

#pragma mark - AVAssetResourceLoaderDelegate

- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader
shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest {
    NSURL *requestURL = loadingRequest.request.URL;
    if (!requestURL) {
        return NO;
    }

    // Use the stored original URL string directly to preserve exact percent-encoding.
    // Do NOT use the requestURL's absoluteString and try to restore it, as that
    // may have already been normalized by NSURL.
    NSURL *originalURL = [NSURL URLWithString:_originalURLString];
    if (!originalURL) {
        // Fallback: try NSURLComponents for stricter parsing
        NSURLComponents *components = [NSURLComponents componentsWithString:_originalURLString];
        originalURL = components.URL;
    }
    if (!originalURL) {
        NSLog(@"just_audio: ResourceLoader: Failed to create URL from original string: %@", _originalURLString);
        return NO;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:originalURL];
    [request setHTTPMethod:@"GET"];

    // Copy custom headers
    if (_headers && [_headers count] > 0) {
        for (NSString *key in _headers) {
            [request setValue:_headers[key] forHTTPHeaderField:key];
        }
    }

    // Handle byte-range requests from AVFoundation
    AVAssetResourceLoadingDataRequest *dataRequest = loadingRequest.dataRequest;
    if (dataRequest) {
        long long offset = dataRequest.requestedOffset;
        long long length = dataRequest.requestedLength;
        if (dataRequest.currentOffset != 0) {
            offset = dataRequest.currentOffset;
            length = dataRequest.requestedLength - (dataRequest.currentOffset - dataRequest.requestedOffset);
        }
        if (offset > 0 || !dataRequest.requestsAllDataToEndOfResource) {
            NSString *rangeValue;
            if (dataRequest.requestsAllDataToEndOfResource) {
                rangeValue = [NSString stringWithFormat:@"bytes=%lld-", offset];
            } else {
                rangeValue = [NSString stringWithFormat:@"bytes=%lld-%lld", offset, offset + length - 1];
            }
            [request setValue:rangeValue forHTTPHeaderField:@"Range"];
        }
    }

    NSLog(@"just_audio: ResourceLoader: Loading %@ (Range: %@)",
          self->_originalURLString,
          [request valueForHTTPHeaderField:@"Range"] ?: @"full");

    NSURLSessionDataTask *task = [_session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        // Remove this task from pending
        @synchronized(self->_pendingTasks) {
            [self->_pendingTasks removeObject:task];
        }

        if (loadingRequest.isCancelled) {
            return;
        }

        if (error) {
            NSLog(@"just_audio: ResourceLoader: Network error: %@ (code=%ld)", error.localizedDescription, (long)error.code);
            [loadingRequest finishLoadingWithError:error];
            return;
        }

        NSHTTPURLResponse *httpResponse = nil;
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            httpResponse = (NSHTTPURLResponse *)response;
        }

        if (!httpResponse) {
            NSLog(@"just_audio: ResourceLoader: Non-HTTP response received");
            NSError *err = [NSError errorWithDomain:@"just_audio" code:-1
                                           userInfo:@{NSLocalizedDescriptionKey: @"Non-HTTP response"}];
            [loadingRequest finishLoadingWithError:err];
            return;
        }

        NSInteger statusCode = httpResponse.statusCode;
        NSLog(@"just_audio: ResourceLoader: Response %ld, Content-Length: %@, Content-Type: %@",
              (long)statusCode,
              httpResponse.allHeaderFields[@"Content-Length"] ?: @"unknown",
              httpResponse.MIMEType ?: @"unknown");

        if (statusCode >= 400) {
            NSLog(@"just_audio: ResourceLoader: HTTP error %ld for URL: %@", (long)statusCode, self->_originalURLString);
            NSError *err = [NSError errorWithDomain:@"just_audio" code:statusCode
                                           userInfo:@{NSLocalizedDescriptionKey:
                                                          [NSString stringWithFormat:@"HTTP %ld", (long)statusCode]}];
            [loadingRequest finishLoadingWithError:err];
            return;
        }

        // Fill content information if requested
        AVAssetResourceLoadingContentInformationRequest *contentInfoRequest = loadingRequest.contentInformationRequest;
        if (contentInfoRequest) {
            // Set content type (UTI)
            NSString *mimeType = httpResponse.MIMEType ?: @"audio/mp4";
            if (@available(iOS 14.0, macOS 11.0, *)) {
                UTType *utType = [UTType typeWithMIMEType:mimeType];
                if (utType) {
                    contentInfoRequest.contentType = utType.identifier;
                } else {
                    contentInfoRequest.contentType = @"public.audio";
                }
            } else {
                // Fallback: convert MIME to UTI
                CFStringRef uti = UTTypeCreatePreferredIdentifierForTag(
                    kUTTagClassMIMEType,
                    (__bridge CFStringRef)mimeType,
                    NULL);
                if (uti) {
                    contentInfoRequest.contentType = (__bridge_transfer NSString *)uti;
                } else {
                    contentInfoRequest.contentType = @"public.audio";
                }
            }

            contentInfoRequest.byteRangeAccessSupported = YES;

            // Determine total content length
            NSString *contentRange = httpResponse.allHeaderFields[@"Content-Range"];
            if (contentRange) {
                // Format: "bytes start-end/total"
                NSArray *slashParts = [contentRange componentsSeparatedByString:@"/"];
                if (slashParts.count == 2) {
                    NSString *totalStr = slashParts[1];
                    if (![totalStr isEqualToString:@"*"]) {
                        contentInfoRequest.contentLength = [totalStr longLongValue];
                    }
                }
            } else {
                // Use Content-Length for non-range responses
                long long expectedLength = httpResponse.expectedContentLength;
                if (expectedLength != NSURLResponseUnknownLength && expectedLength > 0) {
                    contentInfoRequest.contentLength = expectedLength;
                }
            }
        }

        // Provide the data
        if (data && data.length > 0 && dataRequest) {
            [dataRequest respondWithData:data];
        }

        [loadingRequest finishLoading];
    }];

    // Track for cancellation
    @synchronized(_pendingTasks) {
        [_pendingTasks addObject:task];
    }
    [task resume];

    return YES;
}

- (void)resourceLoader:(AVAssetResourceLoader *)resourceLoader
didCancelLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest {
    @synchronized(_pendingTasks) {
        // Cancel all pending tasks (simple approach - could be more granular)
        for (NSURLSessionDataTask *task in [_pendingTasks copy]) {
            [task cancel];
        }
        [_pendingTasks removeAllObjects];
    }
}

#pragma mark - Cleanup

- (void)invalidate {
    @synchronized(_pendingTasks) {
        for (NSURLSessionDataTask *task in [_pendingTasks copy]) {
            [task cancel];
        }
        [_pendingTasks removeAllObjects];
    }
    [_session invalidateAndCancel];
}

- (void)dealloc {
    [self invalidate];
}

@end
