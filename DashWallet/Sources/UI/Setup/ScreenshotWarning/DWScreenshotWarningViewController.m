//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWScreenshotWarningViewController.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWScreenshotWarningViewController ()

@property (readonly, nonatomic, strong) UIImageView *iconImageView;
@property (readonly, nonatomic, strong) UILabel *titleLabel;
@property (readonly, nonatomic, strong) UILabel *descriptionLabel;

@end

NS_ASSUME_NONNULL_END

@implementation DWScreenshotWarningViewController

@synthesize iconImageView = _iconImageView;
@synthesize titleLabel = _titleLabel;
@synthesize descriptionLabel = _descriptionLabel;

- (void)viewDidLoad {
    [super viewDidLoad];

    self.iconImageView.image = [UIImage imageNamed:@"icon_screenshot_warning"];
    self.titleLabel.text = NSLocalizedString(@"WARNING", nil);
    self.descriptionLabel.text = NSLocalizedString(@"Screenshots are visible to other apps and devices. Generate a new recovery phrase and keep it secret.", nil);

    UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[ self.iconImageView, self.titleLabel, self.descriptionLabel ]];
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.alignment = UIStackViewAlignmentCenter;
    stackView.spacing = 4.0;
    [self.view addSubview:stackView];

    [self.iconImageView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [self.titleLabel setContentHuggingPriority:UILayoutPriorityRequired - 1 forAxis:UILayoutConstraintAxisVertical];
    [self.descriptionLabel setContentHuggingPriority:UILayoutPriorityRequired - 2 forAxis:UILayoutConstraintAxisVertical];

    [NSLayoutConstraint activateConstraints:@[
        [stackView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [stackView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.view.trailingAnchor constraintEqualToAnchor:stackView.trailingAnchor],
        [self.view.bottomAnchor constraintEqualToAnchor:stackView.bottomAnchor],
    ]];
}

- (UIImageView *)iconImageView {
    if (_iconImageView == nil) {
        _iconImageView = [[UIImageView alloc] init];
        _iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
    }
    return _iconImageView;
}

- (UILabel *)titleLabel {
    if (_titleLabel == nil) {
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.numberOfLines = 0;
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        _titleLabel.adjustsFontForContentSizeCategory = YES;
        _titleLabel.textColor = [UIColor dw_darkTitleColor];
    }
    return _titleLabel;
}


- (UILabel *)descriptionLabel {
    if (_descriptionLabel == nil) {
        _descriptionLabel = [[UILabel alloc] init];
        _descriptionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _descriptionLabel.numberOfLines = 0;
        _descriptionLabel.textAlignment = NSTextAlignmentCenter;
        _descriptionLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        _descriptionLabel.adjustsFontForContentSizeCategory = YES;
        _descriptionLabel.textColor = [UIColor dw_darkTitleColor];
    }
    return _descriptionLabel;
}

@end
