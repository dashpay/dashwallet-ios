//
//  ZNBubbleView.m
//  ZincWallet
//
//  Created by Aaron Voisine on 3/10/14.
//  Copyright (c) 2014 Aaron Voisine <voisine@gmail.com>
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

#import "ZNBubbleView.h"

#define RADIUS    15.0
#define MARGIN    10.0
#define MAX_WIDTH 300.0

@interface ZNBubbleView ()

@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) CAShapeLayer *arrow;

@end

@implementation ZNBubbleView

+ (instancetype)viewWithText:(NSString *)text center:(CGPoint)center
{
    ZNBubbleView *v = [[self alloc] initWithFrame:CGRectMake(center.x - MARGIN, center.y - MARGIN, MARGIN*2, MARGIN*2)];

    v.text = text;
    return v;
}

+ (instancetype)viewWithText:(NSString *)text tipPoint:(CGPoint)point tipDirection:(ZNBubbleTipDirection)direction
{
    ZNBubbleView *v = [[self alloc] initWithFrame:CGRectMake(0, 0, MARGIN*2, MARGIN*2)];

    v.text = text;
    v.tipDirection = direction;
    v.tipPoint = point;
    return v;
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code
        self.layer.cornerRadius = RADIUS;
        self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.8];

        self.label = [[UILabel alloc] initWithFrame:CGRectMake(MARGIN, MARGIN, frame.size.width - MARGIN*2,
                                                               frame.size.height - MARGIN*2)];
        self.label.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
        self.label.textAlignment = NSTextAlignmentCenter;
        self.label.textColor = [UIColor whiteColor];
        self.label.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:17.0];
        self.label.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.15];
        self.label.shadowOffset = CGSizeMake(0.0, 1.0);
        self.label.numberOfLines = 0;
        [self addSubview:self.label];
    }
    return self;
}

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)setText:(NSString *)text
{
    self.label.text = text;
    [self setNeedsLayout];
}

- (NSString *)text
{
    return self.label.text;
}

- (void)setFont:(UIFont *)font
{
    self.label.font = font;
    [self setNeedsLayout];
}

- (UIFont *)font
{
    return self.label.font;
}

- (void)setTipPoint:(CGPoint)tipPoint
{
    _tipPoint = tipPoint;
    [self setNeedsLayout];
}

- (void)setTipDirection:(ZNBubbleTipDirection)tipDirection
{
    _tipDirection = tipDirection;
    [self setNeedsLayout];
}

- (void)setCustomView:(UIView *)customView
{
    if (_customView) [_customView removeFromSuperview];
    _customView = customView;
    customView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                  UIViewAutoresizingFlexibleBottomMargin;
    if (customView) [self addSubview:customView];
    [self setNeedsLayout];
}

- (instancetype)fadeIn
{
    self.alpha = 0.0;

    [UIView animateWithDuration:UINavigationControllerHideShowBarDuration animations:^{
        self.alpha = 1.0;
    }];

    return self;
}

- (instancetype)fadeOut
{
    [UIView animateWithDuration:UINavigationControllerHideShowBarDuration animations:^{
        self.alpha = 0.0;
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];

    return self;
}

- (instancetype)fadeOutAfterDelay:(NSTimeInterval)delay
{
    [self performSelector:@selector(fadeOut) withObject:nil afterDelay:delay];
    return self;
}

- (void)layoutSubviews
{
    CGPoint center = self.center;
    CGRect rect = [self.label textRectForBounds:CGRectMake(0.0, 0.0, MAX_WIDTH - MARGIN*2, CGFLOAT_MAX)
                   limitedToNumberOfLines:0];

    if (self.customView) {
        if (rect.size.width < self.customView.frame.size.width) rect.size.width = self.customView.frame.size.width;
        rect.size.height += self.customView.frame.size.height + (self.text.length > 0 ? MARGIN : 0);
    }

    if (self.tipPoint.x > 1) { // position bubble to point to tipPoint
        center.x = self.tipPoint.x;
        if (center.x + rect.size.width/2 > MAX_WIDTH) center.x = MAX_WIDTH - rect.size.width/2;
        else if (center.x - rect.size.width/2 < MARGIN*2) center.x = MARGIN*2 + rect.size.width/2;

        center.y = self.tipPoint.y;
        center.y += (self.tipDirection == ZNBubbleTipDirectionUp ? 1 : -1)*((rect.size.height + MARGIN*2)/2 + RADIUS);
    }

    self.frame = CGRectMake(center.x - (rect.size.width + MARGIN*2)/2, center.y - (rect.size.height + MARGIN*2)/2,
                            rect.size.width + MARGIN*2, rect.size.height + MARGIN*2);

    if (self.customView) { // layout customView and label
        self.customView.center = CGPointMake((rect.size.width + MARGIN*2)/2,
                                             self.customView.frame.size.height/2 + MARGIN);
        self.label.frame = CGRectMake(MARGIN, self.customView.frame.size.height + MARGIN*2, self.label.frame.size.width,
                                      self.frame.size.height - (self.customView.frame.size.height + MARGIN*3));
    }
    else self.label.frame = CGRectMake(MARGIN, MARGIN, self.label.frame.size.width, self.frame.size.height - MARGIN*2);

    if (self.tipPoint.x > 1) { // draw tip arrow
        CGMutablePathRef path = CGPathCreateMutable();
        CGFloat x = self.tipPoint.x - (center.x - (rect.size.width + MARGIN*2)/2);

        if (! self.arrow) self.arrow = [[CAShapeLayer alloc] init];
        x = MIN(x, rect.size.width + MARGIN*2 - (RADIUS + 7.5));
        x = MAX(x, self.layer.cornerRadius + 7.5);

        if (self.tipDirection == ZNBubbleTipDirectionUp) {
            CGPathMoveToPoint(path, NULL, 0.0, 7.5);
            CGPathAddLineToPoint(path, NULL, 7.5, 0.0);
            CGPathAddLineToPoint(path, NULL, 15.0, 7.5);
            CGPathAddLineToPoint(path, NULL, 0.0, 7.5);
            self.arrow.position = CGPointMake(x, 0.0);
            self.arrow.anchorPoint = CGPointMake(0.5, 1.0);
        }
        else {
            CGPathMoveToPoint(path, NULL, 0.0, 0.0);
            CGPathAddLineToPoint(path, NULL, 7.5, 7.5);
            CGPathAddLineToPoint(path, NULL, 15.0, 0.0);
            CGPathAddLineToPoint(path, NULL, 0.0, 0.0);
            self.arrow.position = CGPointMake(x, rect.size.height + MARGIN*2);
            self.arrow.anchorPoint = CGPointMake(0.5, 0.0);
        }

        self.arrow.path = path;
        self.arrow.strokeColor = [[UIColor clearColor] CGColor];
        self.arrow.fillColor = [self.backgroundColor CGColor];
        self.arrow.bounds = CGRectMake(0.0, 0.0, 15.0, 7.5);
        [self.layer addSublayer:self.arrow];
        CGPathRelease(path);
    }
    else if (self.arrow) { // remove tip arrow
        [self.arrow removeFromSuperlayer];
        self.arrow = nil;
    }

    [super layoutSubviews];
}

@end
