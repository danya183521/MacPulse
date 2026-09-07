#import "MPNetworkCounters.h"
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface MPNativeSensors : NSObject
- (NSDictionary<NSString *, id> *)sample;
- (void)resetBaselines;
@end
NS_ASSUME_NONNULL_END
