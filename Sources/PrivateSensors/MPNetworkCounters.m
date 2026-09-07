#import "MPNetworkCounters.h"
@implementation MPNetworkCounters {
    NSString *_interface;
    uint64_t _received, _sent;
    double _timestamp;
    BOOL _ready;
}
- (void)reset {
    _ready = NO;
    _interface = nil;
}
- (NSDictionary<NSString *, NSNumber *> *)updateInterface:(NSString *)name
                                                 received:(NSNumber *)received
                                                     sent:(NSNumber *)sent
                                                timestamp:(double)timestamp {
    if (!name || !received || !sent) {
        [self reset];
        return @{};
    }
    uint64_t down = received.unsignedLongLongValue, up = sent.unsignedLongLongValue;
    double seconds = timestamp - _timestamp;
    NSDictionary *rates = @{};
    // Откат 64-битного счётчика означает сброс, а не гигантский скачок трафика.
    BOOL downOK = down >= _received;
    BOOL upOK = up >= _sent;
    if (_ready && [name isEqual:_interface] && seconds > 0 && seconds < 60 && downOK && upOK) {
        rates = @{
            @"download" : @((uint64_t)(down - _received) / seconds),
            @"upload" : @((uint64_t)(up - _sent) / seconds)
        };
    }
    _ready = YES;
    _interface = [name copy];
    _received = down;
    _sent = up;
    _timestamp = timestamp;
    return rates;
}
@end
