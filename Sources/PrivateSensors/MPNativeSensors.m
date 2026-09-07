#import "MPNativeSensors.h"
#import <CoreWLAN/CoreWLAN.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/ps/IOPSKeys.h>
#import <IOKit/ps/IOPowerSources.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <arpa/inet.h>
#import <dlfcn.h>
#import <ifaddrs.h>
#import <mach/mach.h>
#import <net/if.h>
#import <net/if_dl.h>
#import <net/if_mib.h>
#import <sys/mount.h>
#import <sys/sysctl.h>

// Закрытый ABI изолирован в этом файле. Только чтение; отсутствие символов допустимо.
typedef struct {
    uint8_t major, minor, build, reserved;
    uint16_t release;
} MPVersion;
typedef struct {
    uint16_t version, length;
    uint32_t cpu, gpu, memory;
} MPLimits;
typedef struct {
    uint32_t size, type;
    uint8_t attributes;
} MPKeyInfo;
typedef struct {
    uint32_t key;
    MPVersion version;
    MPLimits limits;
    MPKeyInfo info;
    uint8_t result, status, command;
    uint32_t index;
    uint8_t bytes[32];
} MPKey;
_Static_assert(sizeof(MPKey) == 80, "SMC ABI size");
static uint32_t fourCC(const char *s) {
    return ((uint32_t)s[0] << 24) | ((uint32_t)s[1] << 16) | ((uint32_t)s[2] << 8) | (uint8_t)s[3];
}
static NSString *sysString(const char *key) {
    size_t n = 0;
    if (sysctlbyname(key, NULL, &n, NULL, 0) || n == 0)
        return @"Unavailable";
    char *s = calloc(n + 1, 1);
    if (!s)
        return @"Unavailable";
    sysctlbyname(key, s, &n, NULL, 0);
    NSString *v = @(s);
    free(s);
    return v;
}
static uint64_t sysInt(const char *key) {
    uint64_t v = 0;
    size_t n = sizeof(v);
    sysctlbyname(key, &v, &n, NULL, 0);
    return v;
}
static NSDictionary *properties(io_registry_entry_t obj) {
    CFMutableDictionaryRef p = NULL;
    if (IORegistryEntryCreateCFProperties(obj, &p, kCFAllocatorDefault, 0) != KERN_SUCCESS)
        return @{};
    return CFBridgingRelease(p);
}
static NSArray<NSDictionary *> *registry(NSString *cls) {
    io_iterator_t it = 0;
    NSMutableArray *a = [NSMutableArray array];
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(cls.UTF8String), &it) == 0) {
        io_object_t s;
        while ((s = IOIteratorNext(it))) {
            NSMutableDictionary *data = [properties(s) mutableCopy];
            uint64_t identifier = 0;
            if (IORegistryEntryGetRegistryEntryID(s, &identifier) == KERN_SUCCESS)
                data[@"MPRegistryID"] = @(identifier);
            [a addObject:data];
            IOObjectRelease(s);
        }
        IOObjectRelease(it);
    }
    return a;
}

static NSDictionary *networkCounters(void) {
    struct if_nameindex *interfaces = if_nameindex();
    if (!interfaces)
        return @{};
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (struct if_nameindex *item = interfaces; item->if_index; item++) {
        int mib[] = {CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, item->if_index, IFDATA_GENERAL};
        struct ifmibdata data = {0};
        size_t size = sizeof(data);
        // Публичный IFMIB сохраняет 64 бита; NET_RT_IFLIST2 обрезает их для обычных приложений.
        if (sysctl(mib, 6, &data, &size, NULL, 0) == 0 && size == sizeof(data) &&
            (data.ifmd_flags & IFF_UP) && !(data.ifmd_flags & IFF_LOOPBACK)) {
            result[@(item->if_name)] = @[ @(data.ifmd_data.ifi_ibytes), @(data.ifmd_data.ifi_obytes) ];
        }
    }
    if_freenameindex(interfaces);
    return result;
}

@implementation MPNativeSensors {
    NSArray<NSArray<NSNumber *> *> *_ticks;
    MPNetworkCounters *_networkCounters;
    double _previousTime;
    uint64_t _diskRead, _diskWrite;
    BOOL _diskReady;
    NSSet *_diskDevices;
    NSUInteger _count;
    NSDictionary *_slow;
    io_connect_t _smc;
    NSMutableDictionary *_smcInfo;
    NSArray<NSString *> *_smcKeys;
    NSString *_smcError;
    void *_reportLib;
    CFDictionaryRef (*_all)(uint64_t, uint64_t);
    CFTypeRef (*_subscribe)(void *, CFMutableDictionaryRef, CFMutableDictionaryRef *, uint64_t, CFTypeRef);
    CFDictionaryRef (*_samples)(CFTypeRef, CFMutableDictionaryRef, CFTypeRef);
    CFDictionaryRef (*_delta)(CFDictionaryRef, CFDictionaryRef, CFTypeRef);
    CFStringRef (*_group)(CFDictionaryRef);
    CFStringRef (*_name)(CFDictionaryRef);
    CFStringRef (*_unit)(CFDictionaryRef);
    int64_t (*_integer)(CFDictionaryRef, int);
    CFMutableDictionaryRef _channels;
    CFTypeRef _subscription;
    CFDictionaryRef _lastReport;
    NSString *_reportError;
    void *_hidLib;
    CFTypeRef _hidClient;
    CFArrayRef (*_hidServices)(CFTypeRef);
    CFTypeRef (*_hidProperty)(CFTypeRef, CFStringRef);
    CFTypeRef (*_hidEvent)(CFTypeRef, int64_t, int32_t, int64_t);
    double (*_hidValue)(CFTypeRef, int64_t);
}
- (instancetype)init {
    if ((self = [super init])) {
        _hidLib = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
        if (_hidLib) {
            CFTypeRef (*create)(CFAllocatorRef) = dlsym(_hidLib, "IOHIDEventSystemClientCreate");
            void (*match)(CFTypeRef, CFDictionaryRef) = dlsym(_hidLib, "IOHIDEventSystemClientSetMatching");
            _hidServices = dlsym(_hidLib, "IOHIDEventSystemClientCopyServices");
            _hidProperty = dlsym(_hidLib, "IOHIDServiceClientCopyProperty");
            _hidEvent = dlsym(_hidLib, "IOHIDServiceClientCopyEvent");
            _hidValue = dlsym(_hidLib, "IOHIDEventGetFloatValue");
            if (create && match && _hidServices && _hidProperty && _hidEvent && _hidValue) {
                _hidClient = create(NULL);
                if (_hidClient)
                    match(_hidClient,
                          (__bridge CFDictionaryRef) @{@"PrimaryUsagePage" : @0xff00, @"PrimaryUsage" : @5});
            }
        }
        _smcInfo = [NSMutableDictionary dictionary];
        _networkCounters = [MPNetworkCounters new];
        io_iterator_t it = 0;
        if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &it) == 0) {
            io_object_t service;
            while ((service = IOIteratorNext(it))) {
                if (!_smc) {
                    kern_return_t r = IOServiceOpen(service, mach_task_self(), 0, &_smc);
                    if (r)
                        _smcError = [NSString stringWithFormat:@"AppleSMC open: 0x%x", r];
                }
                IOObjectRelease(service);
            }
            IOObjectRelease(it);
        }
        if (!_smc)
            _smcError = _smcError ?: @"AppleSMC service unavailable";
        // На M1 эти ключи сопоставлены с ядрами; на других чипах используем именованные HID-сенсоры.
        if ([sysString("machdep.cpu.brand_string") isEqual:@"Apple M1"])
            _smcKeys =
                @[ @"Tp09", @"Tp0T", @"Tp01", @"Tp05", @"Tp0D", @"Tp0H", @"Tp0L", @"Tp0P", @"Tg05", @"Tg0D" ];
        else
            _smcKeys = @[];
        _reportLib = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY | RTLD_LOCAL);
#define LOAD(field, symbol) field = dlsym(_reportLib, symbol)
        if (_reportLib) {
            LOAD(_all, "IOReportCopyAllChannels");
            LOAD(_subscribe, "IOReportCreateSubscription");
            LOAD(_samples, "IOReportCreateSamples");
            LOAD(_delta, "IOReportCreateSamplesDelta");
            LOAD(_group, "IOReportChannelGetGroup");
            LOAD(_name, "IOReportChannelGetChannelName");
            LOAD(_unit, "IOReportChannelGetUnitLabel");
            LOAD(_integer, "IOReportSimpleGetIntegerValue");
        }
#undef LOAD
        if (_all && _subscribe && _samples && _delta && _group && _name && _unit && _integer) {
            CFDictionaryRef all = _all(0, 0);
            if (all) {
                _channels = CFDictionaryCreateMutableCopy(NULL, 0, all);
                NSArray *items = (__bridge NSArray *)CFDictionaryGetValue(all, CFSTR("IOReportChannels"));
                NSMutableArray *selected = [NSMutableArray array];
                for (NSDictionary *item in items) {
                    CFDictionaryRef ch = (__bridge CFDictionaryRef)item;
                    NSString *g = (__bridge NSString *)_group(ch), *name = (__bridge NSString *)_name(ch),
                             *unit = (__bridge NSString *)_unit(ch);
                    BOOL energyUnit = [@[ @"mJ", @"uJ", @"nJ" ] containsObject:unit ?: @""];
                    BOOL compute = [name hasSuffix:@"CPU Energy"] || [name isEqual:@"GPU Energy"] ||
                                   [name hasPrefix:@"ANE"];
                    if (energyUnit && compute && ([g isEqual:@"Energy Model"] || [g isEqual:@"PMP"]))
                        [selected addObject:item];
                }
                CFDictionarySetValue(_channels, CFSTR("IOReportChannels"), (__bridge CFArrayRef)selected);
                if (selected.count) {
                    CFMutableDictionaryRef subscribed = NULL;
                    _subscription = _subscribe(NULL, _channels, &subscribed, 0, NULL);
                    if (subscribed) {
                        CFRelease(_channels);
                        _channels = subscribed;
                    }
                }
                CFRelease(all);
            }
            if (!_subscription)
                _reportError = @"IOReport Energy Model/PMP subscription unavailable";
        } else
            _reportError = @"libIOReport or required symbols unavailable";
    }
    return self;
}
- (void)dealloc {
    if (_hidClient)
        CFRelease(_hidClient);
    if (_hidLib)
        dlclose(_hidLib);
    if (_smc)
        IOServiceClose(_smc);
    if (_lastReport)
        CFRelease(_lastReport);
    if (_subscription)
        CFRelease(_subscription);
    if (_channels)
        CFRelease(_channels);
    if (_reportLib)
        dlclose(_reportLib);
}
- (void)resetBaselines {
    _ticks = nil;
    [_networkCounters reset];
    _previousTime = 0;
    _diskReady = NO;
    _count = 0;
    if (_lastReport) {
        CFRelease(_lastReport);
        _lastReport = NULL;
    }
}
- (NSNumber *)smcValue:(NSString *)key {
    if (!_smc || key.length != 4)
        return nil;
    MPKey in = {0}, out = {0};
    in.key = fourCC(key.UTF8String);
    size_t size = sizeof(out);
    NSData *cached = _smcInfo[key];
    if (cached)
        [cached getBytes:&in.info length:sizeof(in.info)];
    else {
        in.command = 9;
        if (IOConnectCallStructMethod(_smc, 2, &in, sizeof(in), &out, &size) || out.result ||
            size != sizeof(out))
            return nil;
        in.info = out.info;
        _smcInfo[key] = [NSData dataWithBytes:&out.info length:sizeof(out.info)];
    }
    if (in.info.size > 32 || in.info.size == 0)
        return nil;
    in.command = 5;
    size = sizeof(out);
    if (IOConnectCallStructMethod(_smc, 2, &in, sizeof(in), &out, &size) || out.result || size != sizeof(out))
        return nil;
    if (in.info.type == fourCC("flt ") && in.info.size == 4) {
        float value;
        memcpy(&value, out.bytes, 4);
        return isfinite(value) ? @(value) : nil;
    }
    if (in.info.type == fourCC("sp78") && in.info.size == 2)
        return @((int16_t)((out.bytes[0] << 8) | out.bytes[1]) / 256.0);
    return nil;
}
- (NSDictionary *)thermals {
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    if (_hidClient) {
        NSArray *services = CFBridgingRelease(_hidServices(_hidClient));
        for (id service in services) {
            NSString *name = CFBridgingRelease(_hidProperty((__bridge CFTypeRef)service, CFSTR("Product")));
            CFTypeRef event = _hidEvent((__bridge CFTypeRef)service, 15, 0, 0);
            if (event) {
                double value = _hidValue(event, 15 << 16);
                CFRelease(event);
                if (name && isfinite(value) && value > 0 && value < 150)
                    values[name] = @(value);
            }
        }
    }
    if (values.count)
        return values;
    for (NSString *key in _smcKeys) {
        NSNumber *v = [self smcValue:key];
        if (v && v.doubleValue > 0 && v.doubleValue < 150)
            values[key] = v;
    }
    return values;
}
- (NSDictionary *)power:(double)elapsed {
    if (!_subscription)
        return @{};
    CFDictionaryRef next = _samples(_subscription, _channels, NULL);
    if (!next)
        return @{};
    NSMutableDictionary *power = [NSMutableDictionary dictionary];
    if (_lastReport && elapsed > 0 && elapsed < 60) {
        CFDictionaryRef delta = _delta(_lastReport, next, NULL);
        if (delta) {
            NSArray *items = (__bridge NSArray *)CFDictionaryGetValue(delta, CFSTR("IOReportChannels"));
            for (NSDictionary *item in items) {
                CFDictionaryRef ch = (__bridge CFDictionaryRef)item;
                NSString *name = (__bridge NSString *)_name(ch), *unit = (__bridge NSString *)_unit(ch);
                double divisor = [unit isEqual:@"mJ"]   ? 1e3
                                 : [unit isEqual:@"uJ"] ? 1e6
                                 : [unit isEqual:@"nJ"] ? 1e9
                                                        : 0;
                int64_t energy = _integer(ch, 0);
                if (divisor && energy >= 0 && name)
                    power[name] = @(energy / divisor / elapsed);
            }
            CFRelease(delta);
        }
    }
    if (_lastReport)
        CFRelease(_lastReport);
    _lastReport = next;
    return power;
}
- (NSDictionary *)sample {
    double now = NSProcessInfo.processInfo.systemUptime;
    double elapsed = _previousTime ? now - _previousTime : 0;
    NSMutableDictionary *r = [NSMutableDictionary dictionary];
    host_t host = mach_host_self();
    natural_t ncpu = 0;
    processor_info_array_t info = NULL;
    mach_msg_type_number_t count = 0;
    if (host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &ncpu, &info, &count) == KERN_SUCCESS) {
        NSMutableArray *current = [NSMutableArray array], *loads = [NSMutableArray array];
        double totalBusy = 0, totalTicks = 0;
        for (natural_t i = 0; i < ncpu; i++) {
            NSMutableArray *t = [NSMutableArray array];
            for (int j = 0; j < CPU_STATE_MAX; j++)
                [t addObject:@((uint32_t)info[i * CPU_STATE_MAX + j])];
            [current addObject:t];
            if (_ticks.count == ncpu && elapsed > 0 && elapsed < 60) {
                double busy = 0, total = 0;
                for (int j = 0; j < CPU_STATE_MAX; j++) {
                    uint32_t d = [t[j] unsignedIntValue] - _ticks[i][j].unsignedIntValue;
                    total += d;
                    if (j != CPU_STATE_IDLE)
                        busy += d;
                }
                [loads addObject:total ? @(100 * busy / total) : @0];
                totalBusy += busy;
                totalTicks += total;
            }
        }
        if (totalTicks > 0) {
            r[@"cpu"] = @(100 * totalBusy / totalTicks);
            r[@"cores"] = loads;
        }
        _ticks = current;
        vm_deallocate(mach_task_self(), (vm_address_t)info, count * sizeof(integer_t));
    }
    vm_statistics64_data_t vm = {0};
    mach_msg_type_number_t vmCount = HOST_VM_INFO64_COUNT;
    if (host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vm, &vmCount) == KERN_SUCCESS) {
        double page = vm_kernel_page_size, physical = NSProcessInfo.processInfo.physicalMemory;
        double used = (vm.active_count + vm.inactive_count + vm.speculative_count + vm.wire_count +
                       vm.compressor_page_count) *
                          page -
                      vm.purgeable_count * page - vm.external_page_count * page;
        used = fmax(0, fmin(physical, used));
        r[@"memoryUsed"] = @(used);
        r[@"memoryTotal"] = @(physical);
        r[@"memoryAvailable"] = @(physical - used);
        r[@"memory"] = @(100 * used / physical);
        r[@"wired"] = @(vm.wire_count * page);
        r[@"compressed"] = @(vm.compressor_page_count * page);
        r[@"cached"] = @((vm.external_page_count + vm.purgeable_count) * page);
    }
    mach_port_deallocate(mach_task_self(), host);
    struct xsw_usage swap = {0};
    size_t swapSize = sizeof(swap);
    if (sysctlbyname("vm.swapusage", &swap, &swapSize, NULL, 0) == 0) {
        r[@"swap"] = @(swap.xsu_used);
        r[@"swapTotal"] = @(swap.xsu_total);
    }
    int pressure = 0;
    size_t pressureSize = sizeof(pressure);
    if (sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &pressureSize, NULL, 0) == 0)
        r[@"pressure"] = @(pressure);
    r[@"thermalState"] = @(NSProcessInfo.processInfo.thermalState);
    NSDictionary *net = networkCounters();
    NSMutableDictionary *addresses = [NSMutableDictionary dictionary];
    struct ifaddrs *head = NULL;
    if (getifaddrs(&head) == 0) {
        for (struct ifaddrs *p = head; p; p = p->ifa_next) {
            if (!p->ifa_addr || !(p->ifa_flags & IFF_UP) || (p->ifa_flags & IFF_LOOPBACK))
                continue;
            NSString *name = @(p->ifa_name);
            if (p->ifa_addr->sa_family == AF_INET) {
                char ip[INET_ADDRSTRLEN];
                inet_ntop(AF_INET, &((struct sockaddr_in *)p->ifa_addr)->sin_addr, ip, sizeof(ip));
                addresses[name] = @(ip);
            }
        }
        freeifaddrs(head);
    }
    SCDynamicStoreRef store = SCDynamicStoreCreate(NULL, CFSTR("MacPulse"), NULL, NULL);
    NSDictionary *route =
        store ? CFBridgingRelease(SCDynamicStoreCopyValue(store, CFSTR("State:/Network/Global/IPv4"))) : nil;
    if (!route && store)
        route = CFBridgingRelease(SCDynamicStoreCopyValue(store, CFSTR("State:/Network/Global/IPv6")));
    if (store)
        CFRelease(store);
    NSString *active = route[@"PrimaryInterface"];
    r[@"interface"] = active ?: @"Offline";
    r[@"localIP"] = addresses[active ?: @""] ?: @"Unavailable";
    // Считаем только основной интерфейс, чтобы VPN и мосты не удваивали трафик.
    NSArray *cur = net[active ?: @""];
    if (cur.count == 2) {
        r[@"networkReceivedBytes"] = cur[0];
        r[@"networkSentBytes"] = cur[1];
    }
    [r addEntriesFromDictionary:[_networkCounters updateInterface:active
                                                         received:cur.count == 2 ? cur[0] : nil
                                                             sent:cur.count == 2 ? cur[1] : nil
                                                        timestamp:now]];
    if (_count % 15 == 0 || !_slow) {
        NSMutableDictionary *slow = [NSMutableDictionary dictionary];
        slow[@"model"] = sysString("hw.model");
        slow[@"chip"] = sysString("machdep.cpu.brand_string");
        NSMutableArray *clusters = [NSMutableArray array];
        NSUInteger levels = MIN(sysInt("hw.nperflevels"), 16);
        for (NSUInteger i = 0; i < levels; i++) {
            NSString *prefix = [NSString stringWithFormat:@"hw.perflevel%lu", (unsigned long)i];
            NSString *name = sysString([[prefix stringByAppendingString:@".name"] UTF8String]);
            uint64_t cores = sysInt([[prefix stringByAppendingString:@".physicalcpu"] UTF8String]);
            if (cores)
                [clusters addObject:[NSString stringWithFormat:@"%llu %@", cores, name]];
        }
        slow[@"cpuClusters"] =
            clusters.count ? [clusters componentsJoinedByString:@" · "] : @"Cluster topology unavailable";
        slow[@"os"] = NSProcessInfo.processInfo.operatingSystemVersionString;
        char hostname[256] = {0};
        gethostname(hostname, sizeof(hostname) - 1);
        slow[@"hostname"] = @(hostname);
        NSURL *root = [NSURL fileURLWithPath:NSHomeDirectory()];
        NSDictionary *disk =
            [root resourceValuesForKeys:@[ NSURLVolumeTotalCapacityKey, NSURLVolumeAvailableCapacityKey ]
                                  error:nil];
        NSNumber *total = disk[NSURLVolumeTotalCapacityKey], *avail = disk[NSURLVolumeAvailableCapacityKey];
        if (total && avail && total.doubleValue > 0) {
            slow[@"storageTotal"] = total;
            slow[@"storageAvailable"] = avail;
            slow[@"storageUsed"] = @(total.doubleValue - avail.doubleValue);
            slow[@"storage"] = @(100 * (total.doubleValue - avail.doubleValue) / total.doubleValue);
        }
        NSMutableArray *volumes = [NSMutableArray array];
        for (NSURL *url in [NSFileManager.defaultManager
                 mountedVolumeURLsIncludingResourceValuesForKeys:@[
                     NSURLVolumeNameKey, NSURLVolumeTotalCapacityKey, NSURLVolumeAvailableCapacityKey,
                     NSURLVolumeIsBrowsableKey
                 ]
                                                         options:NSVolumeEnumerationSkipHiddenVolumes]) {
            NSDictionary *p = [url resourceValuesForKeys:@[
                NSURLVolumeNameKey, NSURLVolumeTotalCapacityKey, NSURLVolumeAvailableCapacityKey,
                NSURLVolumeIsBrowsableKey
            ]
                                                   error:nil];
            if ([p[NSURLVolumeIsBrowsableKey] boolValue] && p[NSURLVolumeTotalCapacityKey] &&
                p[NSURLVolumeAvailableCapacityKey])
                [volumes addObject:@{
                    @"name" : p[NSURLVolumeNameKey] ?: url.lastPathComponent,
                    @"total" : p[NSURLVolumeTotalCapacityKey],
                    @"available" : p[NSURLVolumeAvailableCapacityKey]
                }];
        }
        slow[@"volumes"] = volumes;
        CWInterface *wifi = CWWiFiClient.sharedWiFiClient.interface;
        if (wifi && wifi.powerOn) {
            slow[@"wifiSSID"] = wifi.ssid ?: @"Hidden by macOS privacy";
            if (wifi.rssiValue != 0)
                slow[@"wifiSignal"] = @(wifi.rssiValue);
            if (wifi.transmitRate > 0)
                slow[@"wifiLink"] = @(wifi.transmitRate);
            slow[@"wifiNoise"] = @(wifi.noiseMeasurement);
        }
        _slow = slow;
    }
    [r addEntriesFromDictionary:_slow];
    r[@"uptime"] = @(now);
    NSDictionary *battery = registry(@"AppleSmartBattery").firstObject;
    if (battery) {
        NSDictionary *mapping = @{
            @"CurrentCapacity" : @"battery",
            @"CycleCount" : @"cycles",
            @"DesignCapacity" : @"designCapacity",
            @"AppleRawCurrentCapacity" : @"currentCapacity",
            @"AppleRawMaxCapacity" : @"maxCapacity",
            @"IsCharging" : @"charging",
            @"ExternalConnected" : @"externalPower"
        };
        for (NSString *key in mapping)
            if ([battery[key] isKindOfClass:NSNumber.class])
                r[mapping[key]] = battery[key];
        if (battery[@"Temperature"])
            r[@"batteryTemperature"] = @([battery[@"Temperature"] doubleValue] / 100);
        if (battery[@"Voltage"])
            r[@"voltage"] = @([battery[@"Voltage"] doubleValue] / 1000);
        NSNumber *current = battery[@"InstantAmperage"] ?: battery[@"Amperage"];
        if (current)
            r[@"amperage"] = @(current.longLongValue / 1000.0);
        if (battery[@"UpdateTime"])
            r[@"batteryAge"] =
                @(fmax(0, NSDate.date.timeIntervalSince1970 - [battery[@"UpdateTime"] doubleValue]));
        if (r[@"amperage"] && r[@"voltage"])
            r[@"batteryPower"] = @([r[@"amperage"] doubleValue] * [r[@"voltage"] doubleValue]);
        if ([r[@"designCapacity"] doubleValue] > 0 && r[@"maxCapacity"])
            r[@"batteryHealth"] =
                @(100 * [r[@"maxCapacity"] doubleValue] / [r[@"designCapacity"] doubleValue]);
    }
    // Общие сведения о батарее читаем через публичный API; регистр дополняет деталями.
    CFTypeRef sourceInfo = IOPSCopyPowerSourcesInfo();
    if (sourceInfo) {
        NSArray *sources = CFBridgingRelease(IOPSCopyPowerSourcesList(sourceInfo));
        for (id source in sources) {
            NSDictionary *description = (__bridge NSDictionary *)IOPSGetPowerSourceDescription(
                sourceInfo, (__bridge CFTypeRef)source);
            if (![description[@kIOPSTypeKey] isEqual:@kIOPSInternalBatteryType])
                continue;
            NSNumber *current = description[@kIOPSCurrentCapacityKey],
                     *maximum = description[@kIOPSMaxCapacityKey];
            if (current && maximum.doubleValue > 0)
                r[@"battery"] = @(100 * current.doubleValue / maximum.doubleValue);
            if (description[@kIOPSIsChargingKey])
                r[@"charging"] = description[@kIOPSIsChargingKey];
            if (description[@kIOPSPowerSourceStateKey])
                r[@"externalPower"] = @([description[@kIOPSPowerSourceStateKey] isEqual:@kIOPSACPowerValue]);
        }
        CFRelease(sourceInfo);
    }
    NSDictionary *gpu = registry(@"IOAccelerator").firstObject[@"PerformanceStatistics"];
    NSNumber *util = gpu[@"Device Utilization %"];
    if (util && util.doubleValue >= 0 && util.doubleValue <= 100)
        r[@"gpu"] = util;
    if (gpu[@"In use system memory"])
        r[@"gpuMemory"] = gpu[@"In use system memory"];
    NSDictionary *temps = [self thermals];
    r[@"sensors"] = temps;
    double cpu = 0, gpuTemp = 0;
    int cpuN = 0, gpuN = 0;
    for (NSString *key in temps) {
        if (([key hasPrefix:@"Tp"] || [key hasPrefix:@"pACC MTR"] || [key hasPrefix:@"eACC MTR"])) {
            cpu += [temps[key] doubleValue];
            cpuN++;
        }
        if (([key hasPrefix:@"Tg"] || [key hasPrefix:@"GPU MTR"])) {
            gpuTemp += [temps[key] doubleValue];
            gpuN++;
        }
    }
    if (cpuN)
        r[@"cpuTemperature"] = @(cpu / cpuN);
    if (gpuN)
        r[@"gpuTemperature"] = @(gpuTemp / gpuN);
    r[@"thermalReason"] = _smcError
                              ?: (_smcKeys.count ? @"No supported temperature key returned valid data"
                                                 : @"SMC key mapping not validated for this chip");
    NSNumber *systemPower = [self smcValue:@"PSTR"], *packagePower = [self smcValue:@"PHPC"];
    if (systemPower && systemPower.doubleValue >= 0 && systemPower.doubleValue < 1000)
        r[@"systemPower"] = systemPower;
    if (packagePower && packagePower.doubleValue >= 0 && packagePower.doubleValue < 1000)
        r[@"packagePower"] = packagePower;
    NSDictionary *power = [self power:elapsed];
    r[@"energyChannels"] = power;
    for (NSString *name in power) {
        NSString *key = [name hasSuffix:@"CPU Energy"] ? @"cpuPower"
                        : [name isEqual:@"GPU Energy"] ? @"gpuPower"
                        : [name hasPrefix:@"ANE"]      ? @"anePower"
                                                       : nil;
        if (key)
            r[key] = @([r[key] doubleValue] + [power[name] doubleValue]);
    }
    if (r[@"cpuPower"] && r[@"gpuPower"] && r[@"anePower"])
        r[@"computePower"] =
            @([r[@"cpuPower"] doubleValue] + [r[@"gpuPower"] doubleValue] + [r[@"anePower"] doubleValue]);
    r[@"powerReason"] = _reportError ?: @"Waiting for energy delta, or channel/unit absent";
    uint64_t read = 0, write = 0;
    BOOL found = NO;
    NSMutableSet *devices = [NSMutableSet set];
    for (NSDictionary *disk in registry(@"IOBlockStorageDriver")) {
        NSDictionary *s = disk[@"Statistics"];
        if (s[@"Bytes (Read)"] && s[@"Bytes (Write)"]) {
            read += [s[@"Bytes (Read)"] unsignedLongLongValue];
            write += [s[@"Bytes (Write)"] unsignedLongLongValue];
            if (disk[@"MPRegistryID"])
                [devices addObject:disk[@"MPRegistryID"]];
            found = YES;
        }
    }
    if (found && [devices isEqual:_diskDevices] && _diskReady && elapsed > 0 && elapsed < 60 &&
        read >= _diskRead && write >= _diskWrite) {
        r[@"diskRead"] = @((read - _diskRead) / elapsed);
        r[@"diskWrite"] = @((write - _diskWrite) / elapsed);
    }
    _diskDevices = devices;
    _diskReady = found;
    _diskRead = read;
    _diskWrite = write;
    _previousTime = now;
    _count++;
    return r;
}
@end
