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

#import "DWUsernamePendingContentViewController.h"

#import "DWUIKit.h"

@interface DWUsernamePendingContentViewController ()

@property (nonatomic, strong) UILabel *detailLabel;

@end

@implementation DWUsernamePendingContentViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_dashBlueColor];

    [self.view addSubview:self.detailLabel];

    UILayoutGuide *guide = self.view.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.detailLabel.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [self.detailLabel.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [self.detailLabel.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],
        [self.detailLabel.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
    ]];
}

- (void)setUsername:(NSString *)username {
    _username = username;

    self.detailLabel.text = [NSString stringWithFormat:@"Your username %@ is being created on the Dash Network", username];
}

- (UILabel *)detailLabel {
    if (!_detailLabel) {
        UILabel *detailLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        detailLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle3];
        detailLabel.numberOfLines = 0;
        detailLabel.adjustsFontSizeToFitWidth = YES;
        detailLabel.textColor = [UIColor dw_lightTitleColor];
        detailLabel.textAlignment = NSTextAlignmentCenter;
        _detailLabel = detailLabel;
    }

    return _detailLabel;
}

@end
