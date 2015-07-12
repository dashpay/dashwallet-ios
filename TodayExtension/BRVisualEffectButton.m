//
//  BRVisualEffectButton.m
//  BreadWallet
//
//  Created by Henry on 6/14/15.
//  Copyright (c) 2015 Aaron Voisine <voisine@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

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
