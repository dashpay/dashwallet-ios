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

#import "DWPhraseRepairChildViewController.h"

#import "DWProgressView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWPhraseRepairChildViewController ()

@property (null_resettable, nonatomic, strong) UILabel *titleLabel;
@property (null_resettable, nonatomic, strong) DWProgressView *progressView;

@end

NS_ASSUME_NONNULL_END

@implementation DWPhraseRepairChildViewController

- (NSString *)title {
    return self.titleLabel.text;
}

- (void)setTitle:(NSString *)title {
    self.titleLabel.text = title;
}

- (void)setProgress:(float)progress {
    _progress = progress;

    [self.progressView setProgress:progress animated:YES];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor clearColor];

    [self.view addSubview:self.titleLabel];
    [self.view addSubview:self.progressView];

    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor
                                                      constant:16.0],
        [self.view.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor
                                                 constant:16.0],

        [self.progressView.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor
                                                    constant:32.0],
        [self.progressView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.view.trailingAnchor constraintEqualToAnchor:self.progressView.trailingAnchor],
        [self.view.bottomAnchor constraintEqualToAnchor:self.progressView.bottomAnchor],
        [self.progressView.heightAnchor constraintEqualToConstant:5.0],
    ]];
}

- (UILabel *)titleLabel {
    if (_titleLabel == nil) {
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
        _titleLabel.adjustsFontSizeToFitWidth = YES;
        _titleLabel.minimumScaleFactor = 0.5;
        _titleLabel.numberOfLines = 0;
        _titleLabel.textColor = [UIColor dw_darkTitleColor];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
    }
    return _titleLabel;
}

- (DWProgressView *)progressView {
    if (_progressView == nil) {
        _progressView = [[DWProgressView alloc] initWithFrame:CGRectZero];
        _progressView.translatesAutoresizingMaskIntoConstraints = NO;
        _progressView.layer.cornerRadius = 2.0;
        _progressView.layer.masksToBounds = YES;
    }
    return _progressView;
}

@end
