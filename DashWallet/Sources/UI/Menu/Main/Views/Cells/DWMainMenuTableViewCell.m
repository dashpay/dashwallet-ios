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

#import "DWMainMenuTableViewCell.h"

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static UIImage *ImageByType(DWMainMenuItemType type) {
    switch (type) {
        case DWMainMenuItemType_BuySellDash:
            return [UIImage imageNamed:@"menu_buySellDash"];
        case DWMainMenuItemType_Security:
            return [UIImage imageNamed:@"menu_security"];
        case DWMainMenuItemType_Settings:
            return [UIImage imageNamed:@"menu_settings"];
        case DWMainMenuItemType_Tools:
            return [UIImage imageNamed:@"menu_tools"];
        case DWMainMenuItemType_Support:
            return [UIImage imageNamed:@"menu_support"];
    }
}

static NSString *TitleByType(DWMainMenuItemType type) {
    switch (type) {
        case DWMainMenuItemType_BuySellDash:
            return NSLocalizedString(@"Buy & Sell Dash", nil);
        case DWMainMenuItemType_Security:
            return NSLocalizedString(@"Security", nil);
        case DWMainMenuItemType_Settings:
            return NSLocalizedString(@"Settings", nil);
        case DWMainMenuItemType_Tools:
            return NSLocalizedString(@"Tools", nil);
        case DWMainMenuItemType_Support:
            return NSLocalizedString(@"Support", nil);
    }
}

static NSString *DescriptionByType(DWMainMenuItemType type) {
    switch (type) {
        case DWMainMenuItemType_BuySellDash:
            return NSLocalizedString(@"Connect with third party exchanges", nil);
        case DWMainMenuItemType_Security:
            return NSLocalizedString(@"View passphrase, backup wallet…", nil);
        case DWMainMenuItemType_Settings:
            return NSLocalizedString(@"Default currency, shortcuts, about…", nil);
        case DWMainMenuItemType_Tools:
            return NSLocalizedString(@"Import private key…", nil);
        case DWMainMenuItemType_Support:
            return NSLocalizedString(@"Report an Issue", nil);
    }
}

@interface DWMainMenuTableViewCell ()

@property (strong, nonatomic) IBOutlet UIImageView *iconImageView;
@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UILabel *descriptionLabel;

@end

@implementation DWMainMenuTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];

    self.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];
    self.descriptionLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];

    [self dw_pressedAnimation:DWPressedAnimationStrength_Light pressed:highlighted];
}

- (void)setModel:(nullable id<DWMainMenuItem>)model {
    _model = model;

    const DWMainMenuItemType type = model.type;

    self.iconImageView.image = ImageByType(type);
    self.titleLabel.text = TitleByType(type);
    self.descriptionLabel.text = DescriptionByType(type);
}

@end

NS_ASSUME_NONNULL_END
