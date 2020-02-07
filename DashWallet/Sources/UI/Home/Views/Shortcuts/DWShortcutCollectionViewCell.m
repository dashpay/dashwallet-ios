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

#import "DWShortcutCollectionViewCell.h"

#import "DWShortcutAction.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *TitleForAction(DWShortcutAction *action) {
    const DWShortcutActionType type = action.type;
    switch (type) {
        case DWShortcutActionType_SecureWallet:
            return NSLocalizedString(@"Secure Wallet Now",
                                     @"Translate it as short as possible! (24 symbols max)");
        case DWShortcutActionType_ScanToPay:
            return NSLocalizedString(@"Scan to Pay",
                                     @"Translate it as short as possible! (24 symbols max)");
        case DWShortcutActionType_PayToAddress:
            return NSLocalizedString(@"Send to Address",
                                     @"Translate it as short as possible! (24 symbols max)");
        case DWShortcutActionType_BuySellDash:
            return NSLocalizedString(@"Buy / Sell Dash",
                                     @"Translate it as short as possible! (24 symbols max)");
        case DWShortcutActionType_SyncNow:
            return NSLocalizedString(@"Sync Now",
                                     @"Translate it as short as possible! (24 symbols max)");
        case DWShortcutActionType_PayWithNFC:
            return NSLocalizedString(@"Send with NFC",
                                     @"Translate it as short as possible! (24 symbols max)");
        case DWShortcutActionType_LocalCurrency:
            return NSLocalizedString(@"Local Currency",
                                     @"Translate it as short as possible! (24 symbols max)");
        case DWShortcutActionType_ImportPrivateKey:
            return NSLocalizedString(@"Import Private Key",
                                     @"Translate it as short as possible! (24 symbols max)");
        case DWShortcutActionType_SwitchToTestnet:
            return NSLocalizedString(@"Switch to Testnet",
                                     @"Translate it as short as possible! (24 symbols max)");
        case DWShortcutActionType_SwitchToMainnet:
            return NSLocalizedString(@"Switch to Mainnet",
                                     @"Translate it as short as possible! (24 symbols max)");
        case DWShortcutActionType_ReportAnIssue:
            return NSLocalizedString(@"Report an Issue",
                                     @"Translate it as short as possible! (24 symbols max)");
        case DWShortcutActionType_CreateUsername:
            return NSLocalizedString(@"Join Evolution", nil);
        case DWShortcutActionType_AddShortcut:
            return NSLocalizedString(@"Add Shortcut",
                                     @"Translate it as short as possible! (24 symbols max)");
    }

    NSCAssert(NO, @"Unsupported action type");
    return @"";
}

static UIImage *_Nullable IconForAction(DWShortcutAction *action) {
    const DWShortcutActionType type = action.type;
    switch (type) {
        case DWShortcutActionType_SecureWallet: {
            UIImage *image = [UIImage imageNamed:@"shortcut_secureWalletNow"];
            NSCParameterAssert(image);
            return image;
        }
        case DWShortcutActionType_ScanToPay: {
            UIImage *image = [UIImage imageNamed:@"shortcut_scanToPay"];
            NSCParameterAssert(image);
            return image;
        }
        case DWShortcutActionType_PayToAddress: {
            UIImage *image = [UIImage imageNamed:@"shortcut_payToAddress"];
            NSCParameterAssert(image);
            return image;
        }
        case DWShortcutActionType_BuySellDash: {
            UIImage *image = [UIImage imageNamed:@"shortcut_buySellDash"];
            NSCParameterAssert(image);
            return image;
        }
        case DWShortcutActionType_SyncNow: {
            UIImage *image = [UIImage imageNamed:@"shortcut_syncNow"];
            NSCParameterAssert(image);
            return image;
        }
        case DWShortcutActionType_PayWithNFC: {
            UIImage *image = [UIImage imageNamed:@"shortcut_payWithNFC"];
            NSCParameterAssert(image);
            return image;
        }
        case DWShortcutActionType_LocalCurrency: {
            UIImage *image = [UIImage imageNamed:@"shortcut_localCurrency"];
            NSCParameterAssert(image);
            return image;
        }
        case DWShortcutActionType_ImportPrivateKey: {
            UIImage *image = [UIImage imageNamed:@"shortcut_importPrivateKey"];
            NSCParameterAssert(image);
            return image;
        }
        case DWShortcutActionType_SwitchToTestnet: {
            UIImage *image = [UIImage imageNamed:@"shortcut_switchNetwork"];
            NSCParameterAssert(image);
            return image;
        }
        case DWShortcutActionType_SwitchToMainnet: {
            UIImage *image = [UIImage imageNamed:@"shortcut_switchNetwork"];
            NSCParameterAssert(image);
            return image;
        }
        case DWShortcutActionType_ReportAnIssue: {
            UIImage *image = [UIImage imageNamed:@"shortcut_reportAnIssue"];
            NSCParameterAssert(image);
            return image;
        }
        case DWShortcutActionType_CreateUsername: {
            return nil;
        }
        case DWShortcutActionType_AddShortcut: {
            UIImage *image = [UIImage imageNamed:@"shortcut_addShortcut"];
            NSCParameterAssert(image);
            return image;
        }
    }

    NSCAssert(NO, @"Unsupported action type");
    return nil;
}

static UIColor *BackgroundColorForAction(DWShortcutAction *action) {
    const DWShortcutActionType type = action.type;
    switch (type) {
        case DWShortcutActionType_AddShortcut:
            return [UIColor dw_shortcutSpecialBackgroundColor];
        default:
            return [UIColor dw_backgroundColor];
    }
}

static CGFloat AlphaForAction(DWShortcutAction *action) {
    return (action.enabled ? 1.0 : 0.4);
}

static BOOL ShowsGradientLayer(DWShortcutAction *action) {
    const DWShortcutActionType type = action.type;
    switch (type) {
        case DWShortcutActionType_CreateUsername:
            return YES;
        default:
            return NO;
    }
}

static UIColor *TextColor(DWShortcutAction *action) {
    const DWShortcutActionType type = action.type;
    switch (type) {
        case DWShortcutActionType_CreateUsername:
            return [UIColor dw_lightTitleColor];
        default:
            return [UIColor dw_tertiaryTextColor];
    }
}

@interface DWShortcutCollectionViewCell ()

@property (strong, nonatomic) IBOutlet UIView *roundedView;
@property (strong, nonatomic) IBOutlet UIView *centeredView;
@property (strong, nonatomic) IBOutlet UIImageView *iconImageView;
@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (nonatomic, strong) CAGradientLayer *gradientLayer;

@end

@implementation DWShortcutCollectionViewCell

- (void)awakeFromNib {
    [super awakeFromNib];

    self.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption2];

    self.centeredView.backgroundColor = [UIColor clearColor];

    CAGradientLayer *gradientLayer = [CAGradientLayer layer];
    gradientLayer.colors = @[
        (id)[UIColor dw_blueGradientStartColor].CGColor,
        (id)[UIColor dw_dashBlueColor].CGColor,
    ];
    gradientLayer.locations = @[ @0, @1 ];
    gradientLayer.startPoint = CGPointMake(0.25, 0.5);
    gradientLayer.endPoint = CGPointMake(0.75, 0.5);
    [self.roundedView.layer insertSublayer:gradientLayer atIndex:0];
    self.gradientLayer = gradientLayer;
}

- (void)layoutSublayersOfLayer:(CALayer *)layer {
    [super layoutSublayersOfLayer:layer];

    if (layer == self.layer) {
        self.gradientLayer.frame = self.roundedView.bounds;
    }
}

- (void)setModel:(nullable DWShortcutAction *)model {
    _model = model;

    UIColor *backgroundColor = BackgroundColorForAction(model);
    self.roundedView.backgroundColor = backgroundColor;
    self.titleLabel.text = TitleForAction(model);
    self.titleLabel.textColor = TextColor(model);
    self.iconImageView.image = IconForAction(model);
    self.gradientLayer.hidden = !ShowsGradientLayer(model);
    const CGFloat alpha = AlphaForAction(model);
    self.titleLabel.alpha = alpha;
    self.iconImageView.alpha = alpha;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];

    if (self.model.enabled) {
        [self dw_pressedAnimation:DWPressedAnimationStrength_Heavy pressed:highlighted];
    }
}

@end

NS_ASSUME_NONNULL_END
