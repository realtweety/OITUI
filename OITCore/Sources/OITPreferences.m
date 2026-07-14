#import <OITCore/OITPreferences.h>

@interface OITPreferences ()
@property (nonatomic, copy) NSString *domain;
@property (nonatomic, strong) NSDictionary<NSString *, id> *cache;
@end

@implementation OITPreferences

+ (instancetype)preferencesWithDomain:(NSString *)domain {
    OITPreferences *prefs = [OITPreferences new];
    prefs.domain = [domain copy];
    [prefs reload];
    return prefs;
}

- (void)reload {
    CFPreferencesAppSynchronize((__bridge CFStringRef)self.domain);
    CFDictionaryRef values = CFPreferencesCopyMultiple(NULL,
                                                       (__bridge CFStringRef)self.domain,
                                                       kCFPreferencesCurrentUser,
                                                       kCFPreferencesAnyHost);
    NSDictionary *dict = CFBridgingRelease(values);
    self.cache = [dict isKindOfClass:[NSDictionary class]] ? dict : @{};
}

- (id)objectForKey:(NSString *)key default:(id)fallback {
    id value = self.cache[key];
    return value ?: fallback;
}

- (BOOL)boolForKey:(NSString *)key default:(BOOL)fallback {
    id value = self.cache[key];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : fallback;
}

- (CGFloat)floatForKey:(NSString *)key default:(CGFloat)fallback {
    id value = self.cache[key];
    return [value isKindOfClass:[NSNumber class]] ? (CGFloat)[value doubleValue] : fallback;
}

- (NSInteger)integerForKey:(NSString *)key default:(NSInteger)fallback {
    id value = self.cache[key];
    return [value isKindOfClass:[NSNumber class]] ? [value integerValue] : fallback;
}

- (NSString *)stringForKey:(NSString *)key default:(NSString *)fallback {
    id value = self.cache[key];
    return [value isKindOfClass:[NSString class]] && [value length] > 0 ? value : fallback;
}

- (void)setObject:(id)value forKey:(NSString *)key {
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)self.domain);
    NSMutableDictionary *mutableCache = [self.cache mutableCopy] ?: [NSMutableDictionary dictionary];
    mutableCache[key] = value;
    self.cache = mutableCache;
}

- (void)removeObjectForKey:(NSString *)key {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, (__bridge CFStringRef)self.domain);
    NSMutableDictionary *mutableCache = [self.cache mutableCopy];
    [mutableCache removeObjectForKey:key];
    self.cache = mutableCache;
}

- (void)synchronize {
    CFPreferencesAppSynchronize((__bridge CFStringRef)self.domain);
}

@end
