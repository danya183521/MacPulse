#import <Foundation/Foundation.h>
#import <dlfcn.h>
int main(void) {
    @autoreleasepool {
        void *lib = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY);
        if (!lib)
            return 2;
        CFDictionaryRef (*all)(uint64_t, uint64_t) = dlsym(lib, "IOReportCopyAllChannels");
        CFStringRef (*group)(CFDictionaryRef) = dlsym(lib, "IOReportChannelGetGroup");
        CFStringRef (*name)(CFDictionaryRef) = dlsym(lib, "IOReportChannelGetChannelName");
        CFStringRef (*unit)(CFDictionaryRef) = dlsym(lib, "IOReportChannelGetUnitLabel");
        if (!all || !group || !name || !unit)
            return 3;
        NSDictionary *channels = CFBridgingRelease(all(0, 0));
        NSMutableDictionary *counts = [NSMutableDictionary dictionary];
        int ane = 0;
        for (NSDictionary *item in channels[@"IOReportChannels"]) {
            CFDictionaryRef ch = (__bridge CFDictionaryRef)item;
            NSString *g = (__bridge NSString *)group(ch), *n = (__bridge NSString *)name(ch),
                     *u = (__bridge NSString *)unit(ch);
            if (g)
                counts[g] = @([counts[g] intValue] + 1);
            if ([n localizedCaseInsensitiveContainsString:@"ANE"]) {
                ane++;
                printf("ANE candidate: %s | %s | %s\n", g.UTF8String, n.UTF8String, u.UTF8String);
            }
            if ([n hasSuffix:@" Energy"])
                printf("Energy: %s | %s | %s\n", g.UTF8String, n.UTF8String, u.UTF8String);
        }
        printf("ANE-named channels: %d\n", ane);
        for (NSString *g in [[counts allKeys] sortedArrayUsingSelector:@selector(compare:)])
            printf("Group: %s (%d channels)\n", g.UTF8String, [counts[g] intValue]);
        dlclose(lib);
    }
}
