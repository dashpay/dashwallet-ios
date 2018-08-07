//
//  UIFont+SystemFontOverride.m
//  DashWallet
//
//  Created by Sam Westrich on 8/3/18.
//  Copyright © 2018 Aaron Voisine. All rights reserved.
//

#import "UIFont+SystemFontOverride.h"

@implementation UIFont (SystemFontOverride)

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

+ (UIFont *)boldSystemFontOfSize:(CGFloat)fontSize {
    UIFont * font = [UIFont fontWithName:@"Montserrat-Bold" size:fontSize];
    return font;
}

+ (UIFont *)systemFontOfSize:(CGFloat)fontSize {
    UIFont * font = [UIFont fontWithName:@"Montserrat-Regular" size:fontSize];
    return font;
}

+ (UIFont *)systemFontOfSize:(CGFloat)fontSize weight:(UIFontWeight)weight {
    if (weight == UIFontWeightBold) {
            return [UIFont fontWithName:@"Montserrat-Bold" size:fontSize];
    } else if (weight == UIFontWeightThin) {
        return [UIFont fontWithName:@"Montserrat-Thin" size:fontSize];
    } else if (weight == UIFontWeightMedium) {
        return [UIFont fontWithName:@"Montserrat-Medium" size:fontSize];
    } else if (weight == UIFontWeightRegular) {
        return [UIFont fontWithName:@"Montserrat-Regular" size:fontSize];
    } else if (weight == UIFontWeightLight) {
        return [UIFont fontWithName:@"Montserrat-Light" size:fontSize];
    } else if (weight == UIFontWeightUltraLight) {
        return [UIFont fontWithName:@"Montserrat-UltraLight" size:fontSize];
    } else if (weight == UIFontWeightSemibold) {
        return [UIFont fontWithName:@"Montserrat-SemiBold" size:fontSize];
    }
    return [UIFont fontWithName:@"Montserrat-Regular" size:fontSize];
}

#pragma clang diagnostic pop

@end
