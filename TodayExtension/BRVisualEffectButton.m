//
//  BRVisualEffectButton.m
//  BreadWallet
//
//  Created by Henry on 6/17/15.
//  Copyright (c) 2015 Aaron Voisine. All rights reserved.
//

#import "BRVisualEffectButton.h"
#import <NotificationCenter/NotificationCenter.h>

@interface BRVisualEffectButton()
@property (nonatomic, strong) UIVisualEffectView *visualEffectView;
@property (nonatomic, strong) UIImageView *backgroundView;
@end

@implementation BRVisualEffectButton
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self addSubview:self.visualEffectView];
    }
    return self;
}

- (UIVisualEffectView*)visualEffectView {
    if (!_visualEffectView) {
        _visualEffectView = [[UIVisualEffectView alloc] initWithEffect:[UIVibrancyEffect notificationCenterVibrancyEffect]];
        _visualEffectView.frame = self.bounds;
        _visualEffectView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        _visualEffectView.userInteractionEnabled = NO;
        _backgroundView = [[UIImageView alloc] initWithFrame:self.bounds];
        _backgroundView.backgroundColor = [UIColor whiteColor];
        _backgroundView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        [_visualEffectView.contentView addSubview:_backgroundView];
    }
    return _visualEffectView;
}

- (void)setHighlighted:(BOOL)highlighted {
    if(highlighted) {
        self.backgroundView.alpha = 0.6;
    } else {
        self.backgroundView.alpha = 1.0;
    }
    [super setHighlighted:highlighted];
}


@end
