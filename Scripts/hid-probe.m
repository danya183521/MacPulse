#import <Foundation/Foundation.h>
#import <dlfcn.h>
int main(void) {
    @autoreleasepool {
        void *lib = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
        CFTypeRef (*create)(CFAllocatorRef) = dlsym(lib, "IOHIDEventSystemClientCreate");
        void (*match)(CFTypeRef, CFDictionaryRef) = dlsym(lib, "IOHIDEventSystemClientSetMatching");
        CFArrayRef (*services)(CFTypeRef) = dlsym(lib, "IOHIDEventSystemClientCopyServices");
        CFTypeRef (*property)(CFTypeRef, CFStringRef) = dlsym(lib, "IOHIDServiceClientCopyProperty");
        CFTypeRef (*event)(CFTypeRef, int64_t, int32_t, int64_t) = dlsym(lib, "IOHIDServiceClientCopyEvent");
        double (*value)(CFTypeRef, int64_t) = dlsym(lib, "IOHIDEventGetFloatValue");
        if (!create || !match || !services || !property || !event || !value)
            return 2;
        CFTypeRef client = create(NULL);
        match(client, (__bridge CFDictionaryRef) @{@"PrimaryUsagePage" : @0xff00, @"PrimaryUsage" : @5});
        NSArray *s = CFBridgingRelease(services(client));
        for (id item in s) {
            NSString *name = CFBridgingRelease(property((__bridge CFTypeRef)item, CFSTR("Product")));
            CFTypeRef e = event((__bridge CFTypeRef)item, 15, 0, 0);
            if (e) {
                printf("%s %.3f\n", name.UTF8String, value(e, 15 << 16));
                CFRelease(e);
            }
        }
        CFRelease(client);
    }
}
