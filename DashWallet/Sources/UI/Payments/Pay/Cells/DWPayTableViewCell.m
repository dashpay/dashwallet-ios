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

#import "DWPayTableViewCell.h"

#import "DWPayOptionModel.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *TitleForOptionType(DWPayOptionModelType type) {
    switch (type) {
        case DWPayOptionModelType_ScanQR:
            return NSLocalizedString(@"Send by", @"Send by (scanning QR code)");
        case DWPayOptionModelType_Pasteboard:
            return NSLocalizedString(@"Send to copied address", nil);
        case DWPayOptionModelType_NFC:
            return NSLocalizedString(@"Send to", nil);
        default:
            NSCAssert(NO, @"Not supported type");
            return nil;
    }
}

static NSString *DescriptionForOptionType(DWPayOptionModelType type) {
    switch (type) {
        case DWPayOptionModelType_ScanQR:
            return NSLocalizedString(@"Scanning QR code", @"(Send by) Scanning QR code");
        case DWPayOptionModelType_Pasteboard:
            return NSLocalizedString(@"No address copied", nil);
        case DWPayOptionModelType_NFC:
            return NSLocalizedString(@"NFC device", nil);
        default:
            NSCAssert(NO, @"Not supported type");
            return nil;
    }
}

static UIColor *DescriptionColor(DWPayOptionModelType type, BOOL empty) {
    if (empty && type == DWPayOptionModelType_Pasteboard) {
        return [UIColor dw_quaternaryTextColor];
    }
    else {
        return [UIColor dw_darkTitleColor];
    }
}


static UIImage *IconForOptionType(DWPayOptionModelType type) {
    UIImage *image = nil;
    switch (type) {
        case DWPayOptionModelType_ScanQR:
            image = [UIImage imageNamed:@"pay_scan_qr"];
            break;
        case DWPayOptionModelType_Pasteboard:
            image = [UIImage imageNamed:@"pay_copied_address"];
            break;
        case DWPayOptionModelType_NFC:
            image = [UIImage imageNamed:@"pay_nfc"];
            break;
        default:
            NSCAssert(NO, @"Not supported type");
            return nil;
    }
    NSCParameterAssert(image);

    return image;
}

@interface DWPayTableViewCell ()

@property (strong, nonatomic) IBOutlet UIImageView *iconImageView;
@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UILabel *descriptionLabel;

@end

@implementation DWPayTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];

    self.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];
    self.descriptionLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleSubheadline];

    // KVO

    [self mvvm_observe:DW_KEYPATH(self, model.details)
                  with:^(typeof(self) self, NSString *value) {
                      [self updateDetails];
                  }];
}

- (void)setModel:(nullable DWPayOptionModel *)model {
    _model = model;

    DWPayOptionModelType type = model.type;
    self.titleLabel.text = TitleForOptionType(type);
    self.iconImageView.image = IconForOptionType(type);

    [self updateDetails];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];

    [self dw_pressedAnimation:DWPressedAnimationStrength_Light pressed:highlighted];
}

#pragma mark - Private

- (void)updateDetails {
    DWPayOptionModelType type = self.model.type;
    NSString *details = self.model.details;
    NSAssert(details == nil || [details isKindOfClass:NSString.class], @"Unsupported details type");
    const BOOL emptyDetails = details == nil;
    self.descriptionLabel.text = emptyDetails ? DescriptionForOptionType(type) : details;
    self.descriptionLabel.textColor = DescriptionColor(type, emptyDetails);

#if SNAPSHOT
    if (type == DWPayOptionModelType_Pasteboard) {
        // TODO: DP: probably needs to be fixed
        self.accessibilityIdentifier = @"send_pasteboard_button";
    }
#endif /* SNAPSHOT */
}

@end

NS_ASSUME_NONNULL_END
