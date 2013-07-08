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
    static UIImage *bg = nil, *pressed = nil, *disabled = nil, *white = nil, *blue = nil;
    
    if (! bg) {
        bg = [[UIImage imageNamed:@"button-bg.png"]
              resizableImageWithCapInsets:UIEdgeInsetsMake(12.0, 3.0, 12.0, 3.0)];
    }
    
    if (! pressed) {
        pressed = [[UIImage imageNamed:@"button-bg-pressed.png"]
                   resizableImageWithCapInsets:UIEdgeInsetsMake(12.0, 3.0, 12.0, 3.0)];
    }
    
    if (! disabled) {
        disabled = [[UIImage imageNamed:@"button-bg-disabled.png"]
                    resizableImageWithCapInsets:UIEdgeInsetsMake(12.0, 3.0, 12.0, 3.0)];
    }
    
    if (! white) {
        white = [[UIImage imageNamed:@"button-bg-white-pressed.png"]
                 resizableImageWithCapInsets:UIEdgeInsetsMake(15.0, 5.0, 15.0, 5.0)];
    }
    
    if (! blue) {
        blue = [[UIImage imageNamed:@"button-bg-blue.png"]
                resizableImageWithCapInsets:UIEdgeInsetsMake(15.0, 5.0, 15.0, 5.0)];
    }
    
    switch (style) {
        case ZNButtonStyleBlue:
            self.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"bluegradient.png"]];
            self.layer.cornerRadius = 6.0;
            self.layer.shadowColor = [[UIColor blackColor] CGColor];
            self.layer.shadowRadius = 2.0;
            self.layer.shadowOpacity = 0.25;
            self.layer.shadowOffset = CGSizeMake(0.0, 1.0);
            self.layer.masksToBounds = NO;

            [self setBackgroundImage:nil forState:UIControlStateNormal];
            [self setBackgroundImage:white forState:UIControlStateHighlighted];
            [self setBackgroundImage:white forState:UIControlStateDisabled];

            [self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [self setTitleColor:[UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:1.0]
                                 forState:UIControlStateHighlighted];
            [self setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];
            
            self.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-Light" size:17];
            self.titleLabel.shadowOffset = CGSizeMake(0.0, 0.0);

            break;
            
        case ZNButtonStyleGray:
            self.backgroundColor = [UIColor clearColor];
            self.layer.cornerRadius = 0.0;
            self.layer.shadowRadius = 0.0;
            self.layer.shadowOpacity = 1.0;
            self.layer.shadowOffset = CGSizeZero;
            self.layer.masksToBounds = YES;
        
            [self setBackgroundImage:bg forState:UIControlStateNormal];
            [self setBackgroundImage:pressed forState:UIControlStateHighlighted];
            [self setBackgroundImage:disabled forState:UIControlStateDisabled];
            
            [self setTitleColor:[UIColor darkGrayColor] forState:UIControlStateNormal];
            [self setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
            //[self setTitleColor:[UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:1.0]
            //                     forState:UIControlStateHighlighted];
            [self setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];

            [self setTitleShadowColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [self setTitleShadowColor:[UIColor lightGrayColor] forState:UIControlStateHighlighted];
            [self setTitleShadowColor:[UIColor whiteColor] forState:UIControlStateDisabled];

            self.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:15];
            self.titleLabel.shadowOffset = CGSizeMake(0.0, 1.0);

            break;
    }
    
    
    self.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.lineBreakMode = NSLineBreakByClipping;
    
    [self setTitleEdgeInsets:UIEdgeInsetsMake(0, 5, 0, 5)];
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect
{
    // Drawing code
}
*/

@end
