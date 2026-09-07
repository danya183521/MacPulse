#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
typedef struct {
    uint8_t major, minor, build, reserved;
    uint16_t release;
} Ver;
typedef struct {
    uint16_t version, length;
    uint32_t cpu, gpu, memory;
} Limit;
typedef struct {
    uint32_t size, type;
    uint8_t attr;
} Info;
typedef struct {
    uint32_t key;
    Ver ver;
    Limit limit;
    Info info;
    uint8_t result, status, command;
    uint32_t index;
    uint8_t bytes[32];
} Key;
static uint32_t cc(const char *s) {
    return (uint32_t)s[0] << 24 | (uint32_t)s[1] << 16 | (uint32_t)s[2] << 8 | s[3];
}
int main(void) {
    @autoreleasepool {
        io_iterator_t it;
        IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &it);
        io_object_t s;
        while ((s = IOIteratorNext(it))) {
            io_connect_t c = 0;
            int open = IOServiceOpen(s, mach_task_self(), 0, &c);
            printf("open=%x size=%zu\n", open, sizeof(Key));
            if (c) {
                for (NSString *name in @[ @"#KEY", @"Tp09", @"Tp0T", @"Tg05", @"PSTR", @"PHPC", @"PDBR" ]) {
                    Key in = {0}, out = {0};
                    in.key = cc(name.UTF8String);
                    in.command = 9;
                    size_t z = sizeof(out);
                    int ret = IOConnectCallStructMethod(c, 2, &in, sizeof(in), &out, &z);
                    printf("%s metadata status=%x result=%d size=%d type=%x output=%zu", name.UTF8String, ret,
                           out.result, out.info.size, out.info.type, z);
                    if (ret || out.result || out.info.size == 0 || out.info.size > 32) {
                        printf(" unavailable\n");
                        continue;
                    }
                    in.info = out.info;
                    in.command = 5;
                    z = sizeof(out);
                    ret = IOConnectCallStructMethod(c, 2, &in, sizeof(in), &out, &z);
                    printf(" read=%x result=%d", ret, out.result);
                    if (!ret && !out.result && in.info.size == 4) {
                        if (in.info.type == cc("flt ")) {
                            float value = 0;
                            memcpy(&value, out.bytes, 4);
                            printf(" float=%f", value);
                        } else if (in.info.type == cc("ui32")) {
                            uint32_t value = (uint32_t)out.bytes[0] << 24 | (uint32_t)out.bytes[1] << 16 |
                                             (uint32_t)out.bytes[2] << 8 | out.bytes[3];
                            printf(" uint32=%u", value);
                        }
                    }
                    printf("\n");
                }
                IOServiceClose(c);
            }
            IOObjectRelease(s);
        }
        IOObjectRelease(it);
    }
}
