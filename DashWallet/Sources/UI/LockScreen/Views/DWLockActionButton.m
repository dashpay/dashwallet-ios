//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "DWLockActionButton.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const SPACING = 4.0;

@interface DWLockActionButton ()

@property (readonly, nonatomic, strong) UIImageView *imageView;
@property (readonly, nonatomic, strong) UILabel *label;

@end

@implementation DWLockActionButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self lockActionButton_setup];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self lockActionButton_setup];
    }
    return self;
}

- (void)lockActionButton_setup {
    self.backgroundColor = [UIColor clearColor];

    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.contentMode = UIViewContentModeCenter;
    [imageView setContentHuggingPriority:UILayoutPriorityDefaultHigh + 1
                                 forAxis:UILayoutConstraintAxisVertical];
    _imageView = imageView;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.backgroundColor = self.backgroundColor;
    label.numberOfLines = 0;
    label.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
    label.adjustsFontForContentSizeCategory = YES;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.5;
    label.textColor = [UIColor dw_lightTitleColor];
    label.textAlignment = NSTextAlignmentCenter;
    [label setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh + 1
                                           forAxis:UILayoutConstraintAxisVertical];
    _label = label;

    UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[ imageView, label ]];
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.alignment = UIStackViewAlignmentCenter;
    stackView.spacing = SPACING;
    stackView.userInteractionEnabled = NO;
    [self addSubview:stackView];

    [NSLayoutConstraint activateConstraints:@[
        [stackView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    ]];
}

- (nullable UIImage *)image {
    return self.imageView.image;
}

- (void)setImage:(nullable UIImage *)image {
    NSParameterAssert(image);
    self.imageView.image = image;
}

- (nullable NSString *)title {
    return self.label.text;
}

- (void)setTitle:(nullable NSString *)title {
    self.label.text = title;
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];

    self.alpha = enabled ? 1.0 : 0.5;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];

    [UIView animateWithDuration:0.075
                          delay:0.0
                        options:UIViewAnimationCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                         self.alpha = highlighted ? 0.5 : 1.0;
                     }
                     completion:nil];
}

@end

NS_ASSUME_NONNULL_END
