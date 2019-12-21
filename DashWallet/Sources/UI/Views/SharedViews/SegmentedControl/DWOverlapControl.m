//
//    Copyright (c) 2016 Anton Bukov <k06aaa@gmail.com>
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy
//    of this software and associated documentation files (the "Software"), to deal
//    in the Software without restriction, including without limitation the rights
//    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//    copies of the Software, and to permit persons to whom the Software is
//    furnished to do so, subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in
//    all copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//    THE SOFTWARE.
//
//    Based on https://github.com/ML-Works/Overlap/blob/master/Overlap/Classes/MLWOverlapView.m
//

#import "DWOverlapControl.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLWNonTappableView : UIView

@end

@implementation MLWNonTappableView

- (nullable UIView *)hitTest:(CGPoint)point withEvent:(nullable UIEvent *)event {
    UIView *view = [super hitTest:point withEvent:event];
    return (view == self) ? nil : view;
}

- (void)layoutSubviews {
    if (self.hidden) {
        return;
    }
    [super layoutSubviews];
}

@end

//

@interface DWOverlapControl ()

@property (strong, nonatomic) NSArray<UIView *> *overViews;
@property (strong, nonatomic) NSArray<UIView *> *waterViews;
@property (strong, nonatomic) NSArray<CAShapeLayer *> *overMasks;
@property (strong, nonatomic) NSArray<UIBezierPath *> *lastPaths;

@end

@implementation DWOverlapControl

- (instancetype)initWithGenerator:(UIView * (^)(NSUInteger overlapIndex))generator {
    return [self initWithOverlapsCount:2 generator:generator];
}

- (instancetype)initWithOverlapsCount:(NSUInteger)overlapsCount generator:(UIView * (^)(NSUInteger overlapIndex))generator {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        NSMutableArray<CAShapeLayer *> *overMasks = [NSMutableArray array];
        NSMutableArray<UIView *> *waterViews = [NSMutableArray array];
        NSMutableArray<UIView *> *overViews = [NSMutableArray array];
        for (NSInteger index = 0; index < overlapsCount; index++) {
            CAShapeLayer *maskLayer = [CAShapeLayer layer];
            maskLayer.rasterizationScale = [UIScreen mainScreen].scale;
            maskLayer.shouldRasterize = YES;
            [overMasks addObject:maskLayer];

            UIView *waterView = [[MLWNonTappableView alloc] init];
            waterView.clipsToBounds = YES;
            waterView.layer.mask = maskLayer;
            [self addSubview:waterView];
            waterView.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [waterView.topAnchor constraintEqualToAnchor:self.topAnchor],
                [waterView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
                [waterView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
                [waterView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            ]];
            [waterViews addObject:waterView];

            UIView *overView = generator(index);
            [waterView addSubview:overView];
            overView.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[
                [overView.topAnchor constraintEqualToAnchor:self.topAnchor],
                [overView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
                [overView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
                [overView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            ]];
            [overViews addObject:overView];
        }

        _waterViews = waterViews;
        _overViews = overViews;
        _overMasks = overMasks;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.lastPaths) {
        [self overlapWithViewPaths:self.lastPaths];
    }
}

- (void)overlapWithViewPaths:(NSArray<UIBezierPath *> *)paths {
    self.lastPaths = paths;

    for (NSInteger i = 0; i < paths.count; i++) {
        UIView *waterView = self.waterViews[i];
        UIView *overView = self.overViews[i];
        CAShapeLayer *maskLayer = self.overMasks[i];

        if (CGPathIsEmpty(paths[i].CGPath)) {
            if (!waterView.hidden) {
                waterView.hidden = YES;
            }
            continue;
        }

        CGRect frame;
        if (CGPathIsRect(paths[i].CGPath, &frame)) {
            if (CGRectIsEmpty(CGRectIntersection(frame, self.bounds))) {
                if (!waterView.hidden) {
                    waterView.hidden = YES;
                }
                continue;
            }
            else if (waterView.hidden) {
                waterView.hidden = NO;
            }

            if (waterView.layer.mask) {
                waterView.layer.mask = nil;
            }
            if (!CGRectEqualToRect(waterView.frame, frame)) {
                waterView.frame = frame;
                overView.transform = CGAffineTransformMakeTranslation(
                    -frame.origin.x,
                    -frame.origin.y);
            }
            continue;
        }

        if (waterView.hidden) {
            waterView.hidden = NO;
        }
        if (waterView.layer.mask == nil) {
            maskLayer = self.overMasks[i];
            waterView.layer.mask = maskLayer;
            waterView.frame = self.bounds;
            overView.transform = CGAffineTransformIdentity;
        }
        if (!CGPathEqualToPath(maskLayer.path, paths[i].CGPath)) {
            maskLayer.path = paths[i].CGPath;
        }
    }
}

- (void)overlapWithViewFrames:(NSArray<NSValue *> *)frames {
    NSMutableArray<UIBezierPath *> *paths = [NSMutableArray array];
    for (NSValue *value in frames) {
        UIBezierPath *path = [UIBezierPath bezierPathWithRect:value.CGRectValue];
        [paths addObject:path];
    }
    [self overlapWithViewPaths:paths];
}

- (void)overlapWithViews:(NSArray<UIView *> *)views {
    NSMutableArray<UIBezierPath *> *paths = [NSMutableArray array];
    for (UIView *view in views) {
        CGRect frame = (self.window == view.window) ? [view convertRect:view.bounds toView:self] : CGRectZero;
        [paths addObject:[UIBezierPath bezierPathWithRect:frame]];
    }
    [self overlapWithViewPaths:paths];
}

- (void)enumerateOverViews:(void (^)(UIView *overView, NSUInteger index))block {
    for (NSUInteger i = 0; i < self.overViews.count; i++) {
        block(self.overViews[i], i);
    }
}

@end

NS_ASSUME_NONNULL_END
