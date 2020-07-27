#import <FlutterMacOS/FlutterMacOS.h>

@interface AudioSource : NSObject

@property (readonly, nonatomic) NSString* sourceId;

- (instancetype)initWithId:(NSString *)sid;
- (int)buildSequence:(NSMutableArray *)sequence treeIndex:(int)treeIndex;
- (void)findById:(NSString *)sourceId matches:(NSMutableArray<AudioSource *> *)matches;
- (NSArray *)getShuffleOrder;
- (int)shuffle:(int)treeIndex currentIndex:(int)currentIndex;

@end
