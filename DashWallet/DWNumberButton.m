//
//  DWNumberButton.m
//  dashwallet
//
//  Created by Sam Westrich on 8/10/18.
//  Copyright © 2018 Aaron Voisine. All rights reserved.
//

#import "DWNumberButton.h"

@implementation DWNumberButton

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    // Drawing code
}
*/

-(instancetype)initWithCoder:(NSCoder *)aDecoder {
    if (!(self = [super initWithCoder:aDecoder])) return nil;
    self.layer.cornerRadius = 30;
    self.backgroundColor = [UIColor colorWithRed:0 green:0.13 blue:0.38 alpha:1];
    return self;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    
    if (highlighted) {
        self.backgroundColor = [UIColor grayColor];
    } else {
        self.backgroundColor = [UIColor colorWithRed:0 green:0.13 blue:0.38 alpha:1];
    }
    
}

@end
