//
//  DWBlueActionButton.m
//  dashwallet
//
//  Created by Sam Westrich on 8/10/18.
//  Copyright © 2019 Aaron Voisine. All rights reserved.
//

#import "DWBlueActionButton.h"

@implementation DWBlueActionButton

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
