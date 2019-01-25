//
//  DWShareActionButton.m
//  dashwallet
//
//  Created by Sam Westrich on 8/10/18.
//  Copyright © 2019 Aaron Voisine. All rights reserved.
//

#import "DWShareActionButton.h"
#define UIColorFromRGB(rgbValue) [UIColor colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 green:((float)((rgbValue & 0xFF00) >> 8))/255.0 blue:((float)(rgbValue & 0xFF))/255.0 alpha:1.0]

@implementation DWShareActionButton


-(instancetype)initWithCoder:(NSCoder *)aDecoder {
    if (!(self = [super initWithCoder:aDecoder])) return nil;
    self.layer.cornerRadius = self.frame.size.height / 2.0f;
    self.backgroundColor = [UIColor whiteColor];
    self.layer.borderColor = UIColorFromRGB(0x008DE4).CGColor;
    self.layer.borderWidth = 2;
    return self;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    
    if (highlighted) {
        self.layer.borderWidth = 0;
        self.backgroundColor = UIColorFromRGB(0x008DE4);
    } else {
        self.backgroundColor = [UIColor whiteColor];
        self.layer.borderColor = UIColorFromRGB(0x008DE4).CGColor;
        self.layer.borderWidth = 2;
    }
    
}


@end
