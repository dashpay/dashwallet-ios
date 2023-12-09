//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

#import "DWDPWelcomePageViewController.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWDPWelcomePageViewController ()

@property (readonly, assign, nonatomic) NSUInteger index;

@property (null_resettable, strong, nonatomic) UIImageView *imageView;
@property (null_resettable, strong, nonatomic) UILabel *titleLabel;
@property (null_resettable, strong, nonatomic) UILabel *descLabel;

@end

NS_ASSUME_NONNULL_END

@implementation DWDPWelcomePageViewController

- (instancetype)initWithIndex:(NSUInteger)index {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _index = index;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_backgroundColor];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.imageView,
        self.titleLabel,
        self.descLabel,
    ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    [stack setCustomSpacing:68 afterView:self.imageView];
    [self.view addSubview:stack];

    UIView *parent = self.view;
    CGFloat padding = 20;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintGreaterThanOrEqualToAnchor:parent.topAnchor],
        [parent.bottomAnchor constraintGreaterThanOrEqualToAnchor:stack.bottomAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:parent.centerYAnchor],

        [stack.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor
                                            constant:padding],
        [parent.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor
                                              constant:padding],
    ]];
}

- (UIImageView *)imageView {
    if (_imageView == nil) {
        UIImage *image = [UIImage imageNamed:[NSString stringWithFormat:@"dp_welcome_%ld", self.index]];
        _imageView = [[UIImageView alloc] initWithImage:image];
        _imageView.translatesAutoresizingMaskIntoConstraints = NO;
        _imageView.contentMode = UIViewContentModeCenter;
    }
    return _imageView;
}

- (UILabel *)titleLabel {
    if (_titleLabel == nil) {
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont dw_mediumFontOfSize:20];
        _titleLabel.textColor = [UIColor dw_darkTitleColor];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.numberOfLines = 0;
        _titleLabel.adjustsFontForContentSizeCategory = YES;
        NSString *text = nil;
        if (self.index == 0) {
            text = NSLocalizedString(@"Get your Username", nil);
        }
        else if (self.index == 1) {
            text = NSLocalizedString(@"Add your Friends & Family", nil);
        }
        else {
            text = NSLocalizedString(@"Personalize", nil);
        }
        _titleLabel.text = text;
    }
    return _titleLabel;
}

- (UILabel *)descLabel {
    if (_descLabel == nil) {
        _descLabel = [[UILabel alloc] init];
        _descLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _descLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCallout];
        _descLabel.textColor = [UIColor dw_subheaderTextColor];
        _descLabel.textAlignment = NSTextAlignmentCenter;
        _descLabel.numberOfLines = 0;
        _descLabel.adjustsFontForContentSizeCategory = YES;
        NSString *text = nil;
        if (self.index == 0) {
            text = NSLocalizedString(@"Pay to usernames. No more alphanumeric addresses", nil);
        }
        else if (self.index == 1) {
            text = NSLocalizedString(@"Invite your family, find your friends by searching their usernames", nil);
        }
        else {
            text = NSLocalizedString(@"Upload your picture, personalize your identity", nil);
        }
        _descLabel.text = text;
    }
    return _descLabel;
}

@end
