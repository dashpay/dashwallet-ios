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

#pragma clang diagnostic pop

@end
