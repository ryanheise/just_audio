#import <FlutterMacOS/FlutterMacOS.h>

@interface AudioSource : NSObject

@property (readonly, nonatomic) NSString* sourceId;
@property (readwrite, nonatomic) BOOL lazyLoading;

- (instancetype)initWithId:(NSString *)sid;
- (int)buildSequence:(NSMutableArray *)sequence treeIndex:(int)treeIndex;
- (void)findById:(NSString *)sourceId matches:(NSMutableArray<AudioSource *> *)matches;
- (NSArray<NSNumber *> *)getShuffleIndices;
- (void)decodeShuffleOrder:(NSDictionary *)dict;

@end
