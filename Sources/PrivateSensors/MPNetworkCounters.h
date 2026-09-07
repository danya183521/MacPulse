#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Счётчики if_data64 сохраняют трафик быстрых интерфейсов без 32-битного переполнения. Смена маршрута и сброс
// требуют новой базы.
@interface MPNetworkCounters : NSObject
- (NSDictionary<NSString *, NSNumber *> *)updateInterface:(nullable NSString *)name
                                                 received:(nullable NSNumber *)received
                                                     sent:(nullable NSNumber *)sent
                                                timestamp:(double)timestamp;
- (void)reset;
@end
NS_ASSUME_NONNULL_END
