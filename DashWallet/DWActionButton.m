//
//  DWActionButton.m
//  dashwallet
//
//  Created by Sam Westrich on 8/10/18.
//  Copyright © 2018 Aaron Voisine. All rights reserved.
//

#import "DWActionButton.h"

#define UIColorFromRGB(rgbValue) [UIColor colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 green:((float)((rgbValue & 0xFF00) >> 8))/255.0 blue:((float)(rgbValue & 0xFF))/255.0 alpha:1.0]

@implementation DWActionButton

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    // Drawing code
}
*/

-(instancetype)initWithCoder:(NSCoder *)aDecoder {
    if (!(self = [super initWithCoder:aDecoder])) return nil;
    self.layer.cornerRadius = self.frame.size.height / 2.0f;
    self.backgroundColor = UIColorFromRGB(0x008DE4);
    return self;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    
    if (highlighted) {
        self.backgroundColor = [UIColor whiteColor];
        self.layer.borderColor = UIColorFromRGB(0x008DE4).CGColor;
        self.layer.borderWidth = 2;
    } else {
        self.layer.borderWidth = 0;
        self.backgroundColor = UIColorFromRGB(0x008DE4);
    }
    
}


@end
