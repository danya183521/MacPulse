#import "MPNativeSensors.h"
#import <Foundation/Foundation.h>
int main(int argc, const char **argv) {
    @autoreleasepool {
        MPNativeSensors *s = [MPNativeSensors new];
        int n = argc > 1 ? atoi(argv[1]) : 3;
        for (int i = 0; i < n; i++) {
            @autoreleasepool {
                NSDictionary *d = [s sample];
                NSData *j = [NSJSONSerialization dataWithJSONObject:d
                                                            options:NSJSONWritingSortedKeys
                                                              error:nil];
                puts([[NSString alloc] initWithData:j encoding:NSUTF8StringEncoding].UTF8String);
            }
            [NSThread sleepForTimeInterval:1];
        }
    }
}
