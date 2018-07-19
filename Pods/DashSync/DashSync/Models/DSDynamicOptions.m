//
//  Created by Andrew Podkovyrin
//  Copyright © 2018 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//
//  Based on https://github.com/gangverk/GVUserDefaults
//

#import "DSDynamicOptions.h"

#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

enum {
    Type_Char = _C_CHR,
    Type_Bool = _C_BOOL,
    Type_Short = _C_SHT,
    Type_Int = _C_INT,
    Type_Long = _C_LNG,
    Type_LongLong = _C_LNG_LNG,
    Type_UnsignedChar = _C_UCHR,
    Type_UnsignedShort = _C_USHT,
    Type_UnsignedInt = _C_UINT,
    Type_UnsignedLong = _C_ULNG,
    Type_UnsignedLongLong = _C_ULNG_LNG,
    Type_Float = _C_FLT,
    Type_Double = _C_DBL,
    Type_Object = _C_ID,
};

@interface DSDynamicOptions () {
    NSMutableDictionary<NSString *, NSString *> *_private_keyBySelector;
}

@end

@implementation DSDynamicOptions

- (instancetype)init {
    return [self initWithDefaults:nil];
}

- (instancetype)initWithDefaults:(NSDictionary<NSString *, id> *_Nullable)defaults {
    self = [super init];
    if (self) {
        if (defaults) {
            NSMutableDictionary *mutableDefaults = [NSMutableDictionary dictionaryWithCapacity:defaults.count];
            for (NSString *key in defaults) {
                id value = defaults[key];
                NSString *transformedKey = [self defaultsKeyForPropertyName:key];
                mutableDefaults[transformedKey] = value;
            }
            NSUserDefaults *userDefaults = [self userDefaults];
            [userDefaults registerDefaults:mutableDefaults];
        }

        _private_keyBySelector = [NSMutableDictionary dictionary];

        Class klass = [self class];
        objc_property_t *properties = class_copyPropertyList(klass, NULL);

        for (objc_property_t *cursor = properties; properties && *cursor; cursor++) {
            objc_property_t property = *cursor;
            const char *name = property_getName(property);
            const char *attributes = property_getAttributes(property);

            // ignore NSObject @protocol's properties
            if (strcmp(name, "hash") == 0 ||
                strcmp(name, "superclass") == 0 ||
                strcmp(name, "description") == 0 ||
                strcmp(name, "debugDescription") == 0) {

                continue;
            }

            char *getter = strstr(attributes, ",G");
            if (getter) {
                getter = strdup(getter + 2);
                getter = strsep(&getter, ",");
            }
            else {
                getter = strdup(name);
            }
            SEL getterSel = sel_registerName(getter);
            free(getter);

            char *setter = strstr(attributes, ",S");
            if (setter) {
                setter = strdup(setter + 2);
                setter = strsep(&setter, ",");
            }
            else {
                asprintf(&setter, "set%c%s:", toupper(name[0]), name + 1);
            }
            SEL setterSel = sel_registerName(setter);
            free(setter);

            NSString *nameString = [NSString stringWithFormat:@"%s", name];
            NSString *key = [self defaultsKeyForPropertyName:nameString];
            _private_keyBySelector[NSStringFromSelector(getterSel)] = key;
            _private_keyBySelector[NSStringFromSelector(setterSel)] = key;

            IMP getterImp = NULL;
            IMP setterImp = NULL;
            char type = attributes[1];
            switch (type) {
                case Type_Short:
                case Type_Long:
                case Type_LongLong:
                case Type_UnsignedChar:
                case Type_UnsignedShort:
                case Type_UnsignedInt:
                case Type_UnsignedLong:
                case Type_UnsignedLongLong:
                    getterImp = (IMP)longLongGetter;
                    setterImp = (IMP)longLongSetter;
                    break;

                case Type_Bool:
                case Type_Char:
                    getterImp = (IMP)boolGetter;
                    setterImp = (IMP)boolSetter;
                    break;

                case Type_Int:
                    getterImp = (IMP)integerGetter;
                    setterImp = (IMP)integerSetter;
                    break;

                case Type_Float:
                    getterImp = (IMP)floatGetter;
                    setterImp = (IMP)floatSetter;
                    break;

                case Type_Double:
                    getterImp = (IMP)doubleGetter;
                    setterImp = (IMP)doubleSetter;
                    break;

                case Type_Object:
                    getterImp = (IMP)objectGetter;
                    setterImp = (IMP)objectSetter;
                    break;

                default:
                    NSAssert(NO, @"Unsupported type of property \"%s\" in class <%@> attributes \"%s\"", name, self, attributes);
                    continue;
                    break;
            }

            char types[5];

            snprintf(types, 4, "%c@:", type);
            class_addMethod(klass, getterSel, getterImp, types);

            snprintf(types, 5, "v@:%c", type);
            class_addMethod(klass, setterSel, setterImp, types);
        }

        free(properties);
    }
    return self;
}

- (NSUserDefaults *)userDefaults {
    return [NSUserDefaults standardUserDefaults];
}

- (NSString *)defaultsKeyForPropertyName:(NSString *)propertyName {
    return propertyName;
}

#pragma mark Private

- (NSString *)private_defaultsKeyForSelector:(SEL)selector {
    return _private_keyBySelector[NSStringFromSelector(selector)];
}

#pragma mark Implementations

static long long longLongGetter(DSDynamicOptions *self, SEL _cmd) {
    NSString *key = [self private_defaultsKeyForSelector:_cmd];
    NSUserDefaults *userDefaults = [self userDefaults];
    return [[userDefaults objectForKey:key] longLongValue];
}

static void longLongSetter(DSDynamicOptions *self, SEL _cmd, long long value) {
    NSString *key = [self private_defaultsKeyForSelector:_cmd];
    NSNumber *object = [NSNumber numberWithLongLong:value];
    NSUserDefaults *userDefaults = [self userDefaults];
    [userDefaults setObject:object forKey:key];
}

static BOOL boolGetter(DSDynamicOptions *self, SEL _cmd) {
    NSString *key = [self private_defaultsKeyForSelector:_cmd];
    NSUserDefaults *userDefaults = [self userDefaults];
    return [userDefaults boolForKey:key];
}

static void boolSetter(DSDynamicOptions *self, SEL _cmd, BOOL value) {
    NSString *key = [self private_defaultsKeyForSelector:_cmd];
    NSUserDefaults *userDefaults = [self userDefaults];
    [userDefaults setBool:value forKey:key];
}

static NSInteger integerGetter(DSDynamicOptions *self, SEL _cmd) {
    NSString *key = [self private_defaultsKeyForSelector:_cmd];
    NSUserDefaults *userDefaults = [self userDefaults];
    return [userDefaults integerForKey:key];
}

static void integerSetter(DSDynamicOptions *self, SEL _cmd, NSInteger value) {
    NSString *key = [self private_defaultsKeyForSelector:_cmd];
    NSUserDefaults *userDefaults = [self userDefaults];
    [userDefaults setInteger:value forKey:key];
}

static float floatGetter(DSDynamicOptions *self, SEL _cmd) {
    NSString *key = [self private_defaultsKeyForSelector:_cmd];
    NSUserDefaults *userDefaults = [self userDefaults];
    return [userDefaults floatForKey:key];
}

static void floatSetter(DSDynamicOptions *self, SEL _cmd, float value) {
    NSString *key = [self private_defaultsKeyForSelector:_cmd];
    NSUserDefaults *userDefaults = [self userDefaults];
    [userDefaults setFloat:value forKey:key];
}

static double doubleGetter(DSDynamicOptions *self, SEL _cmd) {
    NSString *key = [self private_defaultsKeyForSelector:_cmd];
    NSUserDefaults *userDefaults = [self userDefaults];
    return [userDefaults doubleForKey:key];
}

static void doubleSetter(DSDynamicOptions *self, SEL _cmd, double value) {
    NSString *key = [self private_defaultsKeyForSelector:_cmd];
    NSUserDefaults *userDefaults = [self userDefaults];
    [userDefaults setDouble:value forKey:key];
}

static id objectGetter(DSDynamicOptions *self, SEL _cmd) {
    NSString *key = [self private_defaultsKeyForSelector:_cmd];
    NSUserDefaults *userDefaults = [self userDefaults];
    return [userDefaults objectForKey:key];
}

static void objectSetter(DSDynamicOptions *self, SEL _cmd, id object) {
    NSString *key = [self private_defaultsKeyForSelector:_cmd];
    NSUserDefaults *userDefaults = [self userDefaults];
    if (object) {
        [userDefaults setObject:object forKey:key];
    }
    else {
        [userDefaults removeObjectForKey:key];
    }
}

@end

NS_ASSUME_NONNULL_END
