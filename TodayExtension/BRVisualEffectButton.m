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
@property (nonatomic, strong) UIImageView *viewOnTopOfVisualEffectView;
@property (nonatomic, strong) UIVisualEffectView *visualEffectView;
@property (nonatomic, strong) UIImageView *backgroundView;
@end

@implementation BRVisualEffectButton
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self addSubview:self.visualEffectView];
        [self insertSubview:self.viewOnTopOfVisualEffectView aboveSubview:self.visualEffectView];
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
        _backgroundView.contentMode = UIViewContentModeScaleAspectFit;
        _backgroundView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        [_visualEffectView.contentView addSubview:_backgroundView];
    }
    return _visualEffectView;
}

- (UIImageView*)viewOnTopOfVisualEffectView {
    if (!_viewOnTopOfVisualEffectView) {
        _viewOnTopOfVisualEffectView = [[UIImageView alloc] initWithFrame:self.bounds];
        _viewOnTopOfVisualEffectView.userInteractionEnabled = NO;
        _viewOnTopOfVisualEffectView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        _viewOnTopOfVisualEffectView.contentMode = UIViewContentModeScaleAspectFit;
        _viewOnTopOfVisualEffectView.backgroundColor = [UIColor whiteColor];
        _viewOnTopOfVisualEffectView.alpha = 0.6;
    }
    return _viewOnTopOfVisualEffectView;
}

- (void)setImage:(UIImage *)image forState:(UIControlState)state{
    self.backgroundView.image = image;
    self.viewOnTopOfVisualEffectView.image = image;
    self.backgroundView.backgroundColor = [UIColor clearColor];
    self.viewOnTopOfVisualEffectView.backgroundColor = [UIColor clearColor];
}

- (void)setHighlighted:(BOOL)highlighted {
    if(highlighted) {
        self.viewOnTopOfVisualEffectView.hidden = YES;
    } else {
        self.viewOnTopOfVisualEffectView.hidden = NO;
    }
    [super setHighlighted:highlighted];
}


@end
