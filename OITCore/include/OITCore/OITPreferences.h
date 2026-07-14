#pragma once
#import <Foundation/Foundation.h>

@interface OITPreferences : NSObject

+ (instancetype)preferencesWithDomain:(NSString *)domain;

- (BOOL)boolForKey:(NSString *)key default:(BOOL)fallback;
- (CGFloat)floatForKey:(NSString *)key default:(CGFloat)fallback;
- (NSInteger)integerForKey:(NSString *)key default:(NSInteger)fallback;
- (NSString *)stringForKey:(NSString *)key default:(NSString *)fallback;
- (id)objectForKey:(NSString *)key default:(id)fallback;

- (void)setObject:(id)value forKey:(NSString *)key;
- (void)removeObjectForKey:(NSString *)key;
- (void)synchronize;

- (void)reload;

@end
