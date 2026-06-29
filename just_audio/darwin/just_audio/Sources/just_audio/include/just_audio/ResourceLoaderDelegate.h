#import <AVFoundation/AVFoundation.h>

/// A custom AVAssetResourceLoaderDelegate that intercepts HTTP(S) requests
/// made by AVFoundation and handles them through NSURLSession.
///
/// This is necessary because iOS 17+ changed the URL parser to RFC 3986,
/// which normalizes percent-encoded characters in query strings (e.g.
/// %2B → +, %3D → =). For signed/verified URLs, this normalization
/// breaks server-side signature validation.
///
/// By using a custom URL scheme, AVFoundation delegates all network
/// loading to us, allowing us to make HTTP requests with the exact
/// original URL preserving percent-encoding.
@interface ResourceLoaderDelegate : NSObject <AVAssetResourceLoaderDelegate>

/// The original HTTP(S) URL with preserved percent-encoding.
@property (readonly, nonatomic) NSString *originalURLString;

/// Custom URL scheme prefix used to intercept requests.
+ (NSString *)customSchemePrefix;

/// Converts an HTTP(S) URL to a custom-scheme URL for interception.
/// e.g. https://example.com → just-audio-https://example.com
+ (NSString *)interceptedURLString:(NSString *)urlString;

/// Returns YES if the given URL string uses the custom interception scheme.
+ (BOOL)isInterceptedURLString:(NSString *)urlString;

- (instancetype)initWithOriginalURLString:(NSString *)originalURLString headers:(NSDictionary *)headers;

/// Cancels any pending requests and cleans up resources.
- (void)invalidate;

@end
