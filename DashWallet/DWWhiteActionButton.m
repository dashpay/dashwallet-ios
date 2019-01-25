//
//  DWWhiteActionButton.m
//  dashwallet
//
//  Created by Sam Westrich on 8/10/18.
//  Copyright © 2019 Aaron Voisine. All rights reserved.
//

#import "DWWhiteActionButton.h"
#define UIColorFromRGB(rgbValue) [UIColor colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 green:((float)((rgbValue & 0xFF00) >> 8))/255.0 blue:((float)(rgbValue & 0xFF))/255.0 alpha:1.0]

@implementation DWWhiteActionButton


-(instancetype)initWithCoder:(NSCoder *)aDecoder {
    if (!(self = [super initWithCoder:aDecoder])) return nil;
    self.layer.cornerRadius = self.frame.size.height / 2.0f;
    self.backgroundColor = [UIColor whiteColor];
    return self;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    
    if (highlighted) {
        self.backgroundColor = UIColorFromRGB(0x008DE4);
        self.layer.borderColor = [UIColor whiteColor].CGColor;
        self.layer.borderWidth = 2;
    } else {
        self.layer.borderWidth = 0;
        self.backgroundColor = [UIColor whiteColor];
    }
    
}


@end
