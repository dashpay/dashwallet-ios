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

#import "DWSecurityStatusView.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSecurityStatusView ()

@property (strong, nonatomic) IBOutlet UIView *contentView;
@property (strong, nonatomic) IBOutlet UIImageView *iconImageView;
@property (strong, nonatomic) IBOutlet UILabel *descriptionLabel;
@property (strong, nonatomic) IBOutlet UILabel *levelLabel;

@end

@implementation DWSecurityStatusView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    [[NSBundle mainBundle] loadNibNamed:NSStringFromClass([self class]) owner:self options:nil];
    [self addSubview:self.contentView];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.contentView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.widthAnchor],
    ]];

    self.descriptionLabel.textColor = [UIColor dw_secondaryTextColor];
    self.descriptionLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];
    self.descriptionLabel.text = NSLocalizedString(@"Security Level", nil);

    self.levelLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle3];

    // configure with default level
    self.securityLevel = DWSecurityLevel_None;
}

- (void)setSecurityLevel:(DWSecurityLevel)securityLevel {
    _securityLevel = securityLevel;

    NSString *text = nil;
    UIColor *color = nil;
    UIImage *image = [UIImage imageNamed:@"icon_security_ok"];
    switch (securityLevel) {
        case DWSecurityLevel_None:
            text = NSLocalizedString(@"None", @"adjective, security level");
            color = [UIColor dw_redColor];
            image = [UIImage imageNamed:@"icon_security_excl"];
            break;
        case DWSecurityLevel_Low:
            text = NSLocalizedString(@"Low", @"adjective, security level");
            color = [UIColor dw_orangeColor];
            break;
        case DWSecurityLevel_Medium:
            text = NSLocalizedString(@"Medium", @"adjective, security level");
            color = [UIColor dw_orangeColor];
            break;
        case DWSecurityLevel_High:
            text = NSLocalizedString(@"High", @"adjective, security level");
            color = [UIColor dw_dashBlueColor];
            break;
        case DWSecurityLevel_VeryHigh:
            text = NSLocalizedString(@"Very High", @"adjective, security level");
            color = [UIColor dw_greenColor];
            break;
    }

    self.iconImageView.image = image;
    self.iconImageView.tintColor = color;
    self.levelLabel.textColor = color;
    self.levelLabel.text = text;
}

@end

NS_ASSUME_NONNULL_END
