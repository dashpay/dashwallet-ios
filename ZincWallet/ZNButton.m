//
//  ZNButton.m
//  ZincWallet
//
//  Created by Aaron Voisine on 6/14/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNButton.h"
#import <QuartzCore/QuartzCore.h>

@implementation ZNButton

- (instancetype)init
{
    if (! (self = [super init])) return nil;
    
    [self setStyle:0];
    
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    if (! (self = [super initWithCoder:aDecoder])) return nil;
    
    [self setStyle:0];
    
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if (! (self = [super initWithFrame:frame])) return nil;

    [self setStyle:0];

    return self;
}

- (void)setStyle:(ZNButtonStyle)style
{
    static UIImage *white = nil, *whitepressed = nil, *blue = nil, *bluepressed = nil, *disabled = nil;
    
    if (! white) {
        white = [[UIImage imageNamed:@"button-bg-white.png"]
                 resizableImageWithCapInsets:UIEdgeInsetsMake(15.0, 5.0, 15.0, 5.0)];
        whitepressed = [[UIImage imageNamed:@"button-bg-white-pressed.png"]
                        resizableImageWithCapInsets:UIEdgeInsetsMake(22.0, 5.0, 22.0, 5.0)];
        blue = [[UIImage imageNamed:@"button-bg-blue.png"]
                resizableImageWithCapInsets:UIEdgeInsetsMake(38.0, 5.0, 5.0, 5.0)];
        bluepressed = [[UIImage imageNamed:@"button-bg-blue-pressed.png"]
                       resizableImageWithCapInsets:UIEdgeInsetsMake(22.0, 5.0, 22.0, 5.0)];
        disabled = [[UIImage imageNamed:@"button-bg-disabled.png"]
                    resizableImageWithCapInsets:UIEdgeInsetsMake(15.0, 5.0, 15.0, 5.0)];
    }
    
    switch (style) {
        case ZNButtonStyleWhite:
            self.layer.shadowRadius = 3.0;
            self.layer.shadowOpacity = 0.15;
            self.layer.shadowOffset = CGSizeMake(0.0, 1.0);
            
            [self setBackgroundImage:white forState:UIControlStateNormal];
            [self setBackgroundImage:whitepressed forState:UIControlStateHighlighted];
            [self setBackgroundImage:disabled forState:UIControlStateDisabled];
            
            [self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [self setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];

            self.titleLabel.shadowOffset = CGSizeMake(0.0, 0.0);

            break;

        case ZNButtonStyleBlue:
            self.layer.shadowRadius = 2.0;
            self.layer.shadowOpacity = 0.1;
            self.layer.shadowOffset = CGSizeMake(0.0, 1.0);

            [self setBackgroundImage:blue forState:UIControlStateNormal];
            [self setBackgroundImage:bluepressed forState:UIControlStateHighlighted];
            [self setBackgroundImage:disabled forState:UIControlStateDisabled];

            [self setTitleColor:[UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:1.0]
             forState:UIControlStateNormal];
            [self setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
            [self setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];
            
            self.titleLabel.shadowOffset = CGSizeMake(0.0, 0.0);

            break;
                        
        case ZNButtonStyleNone:
            self.layer.shadowOpacity = 0.0;
            [self setBackgroundImage:nil forState:UIControlStateNormal];
            [self setBackgroundImage:nil forState:UIControlStateHighlighted];
            [self setBackgroundImage:nil forState:UIControlStateDisabled];
            
            [self setTitleColor:[UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:1.0] forState:UIControlStateNormal];
            [self setTitleColor:[UIColor colorWithRed:0.0 green:0.25 blue:0.5 alpha:1.0]
             forState:UIControlStateHighlighted];
            [self setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];
            
            self.titleLabel.shadowOffset = CGSizeMake(0.0, 1.0);
    }

    self.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:17];
    self.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.lineBreakMode = NSLineBreakByClipping;
    self.titleEdgeInsets = UIEdgeInsetsMake(0, 5, 0, 5);
}

@end
