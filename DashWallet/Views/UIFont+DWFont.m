//  
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

// Original idea: https://useyourloaf.com/blog/using-a-custom-font-with-dynamic-type/

#import "UIFont+DWFont.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Helper

@interface DWFontDescription : NSObject

@property (readonly, nonatomic, assign) CGFloat fontSize;
@property (readonly, nonatomic, assign) CGFloat maxSize;
@property (readonly, nonatomic, copy) NSString *fontName;

@end

@implementation DWFontDescription

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    self = [super init];
    if (self) {
        _fontSize = [dictionary[@"fontSize"] doubleValue];
        _maxSize = [dictionary[@"maxSize"] doubleValue];
        _fontName = dictionary[@"fontName"];
    }
    return self;
}

@end

@interface DWScaledFont : NSObject

@property (readonly, nonatomic, copy) NSDictionary <UIFontTextStyle, DWFontDescription *> *styles;

@end

@implementation DWScaledFont

+ (instancetype)sharedInstance {
    static DWScaledFont *_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[self alloc] init];
    });
    return _sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURL *url = [[NSBundle mainBundle] URLForResource:@"Montserrat" withExtension:@"plist"];
        NSDictionary *data = [NSDictionary dictionaryWithContentsOfURL:url];
        NSParameterAssert(data);
        
        NSMutableDictionary <UIFontTextStyle, DWFontDescription *> *styles = [NSMutableDictionary dictionary];
        for (UIFontTextStyle textStyle in data.allKeys) {
            NSDictionary *dictionary = data[textStyle];
            DWFontDescription *fontDescription = [[DWFontDescription alloc] initWithDictionary:dictionary];
            styles[textStyle] = fontDescription;
        }
        _styles = [styles copy];
    }
    return self;
}

@end

#pragma mark - Category

@implementation UIFont (DWFont)

+ (instancetype)dw_fontForTextStyle:(UIFontTextStyle)textStyle {
    DWScaledFont *scaledFont = [DWScaledFont sharedInstance];
    DWFontDescription *fontDescription = scaledFont.styles[textStyle];
    if (!fontDescription) {
        NSAssert(NO, @"Text style %@ is not defined in plist", textStyle);
        return [UIFont preferredFontForTextStyle:textStyle];
    }
    
    UIFont *font = [UIFont fontWithName:fontDescription.fontName size:fontDescription.fontSize];
    if (!font) {
        NSAssert(NO, @"Font for text style %@ is invalid", textStyle);
        return [UIFont preferredFontForTextStyle:textStyle];
    }
    
    UIFontMetrics *fontMetrics = [UIFontMetrics metricsForTextStyle:textStyle];
    UIFont *resultFont = nil;
    if (fontDescription.maxSize > 0) {
        resultFont = [fontMetrics scaledFontForFont:font maximumPointSize:fontDescription.maxSize];
    }
    else {
        resultFont = [fontMetrics scaledFontForFont:font];
    }
    
    return resultFont;
}

@end

NS_ASSUME_NONNULL_END
