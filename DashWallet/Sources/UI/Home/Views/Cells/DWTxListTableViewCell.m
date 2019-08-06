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

#import "DWTxListTableViewCell.h"

#import <DashSync/DashSync.h>

#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWTxListTableViewCell ()

@property (strong, nonatomic) IBOutlet UILabel *addressLabel;
@property (strong, nonatomic) IBOutlet UILabel *dateLabel;
@property (strong, nonatomic) IBOutlet UILabel *dashAmountLabel;
@property (strong, nonatomic) IBOutlet UILabel *fiatAmountLabel;

@property (nullable, nonatomic, weak) id<DWTransactionListDataProviderProtocol> dataProvider;

@property (nonatomic, assign) uint64_t dashAmount;
@property (nonatomic, strong) UIColor *dashAmountTintColor;

@end

@implementation DWTxListTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];

    self.addressLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
    self.dateLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption2];
    self.dashAmountLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];
    self.fiatAmountLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption2];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contentSizeCategoryDidChangeNotification:)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];

    [self dw_pressedAnimation:DWPressedAnimationStrength_Light pressed:highlighted];
}

- (void)configureWithTransaction:(DSTransaction *)transaction
                    dataProvider:(id<DWTransactionListDataProviderProtocol>)dataProvider {
    NSParameterAssert(dataProvider);

    self.dataProvider = dataProvider;

    // TODO: refactor logic below into model's

    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;

    const uint64_t sent = [account amountSentByTransaction:transaction];
    const uint64_t received = [account amountReceivedFromTransaction:transaction];

    NSString *address = nil;
    if (sent > 0) {
        for (NSString *outputAddress in transaction.outputAddresses) {
            if ([outputAddress isKindOfClass:NSString.class]) {
                address = outputAddress;
                break;
            }
        }
    }
    else {
        for (NSString *inputAddress in transaction.inputAddresses) {
            if ([inputAddress isKindOfClass:NSString.class]) {
                address = inputAddress;
                break;
            }
        }
    }

    uint64_t dashAmount;
    UIColor *tintColor = nil;
    if (sent > 0 && received == sent) {
        // moved
        dashAmount = sent;
        tintColor = [UIColor dw_darkTitleColor];
    }
    else if (sent > 0) {
        // sent
        dashAmount = received - sent;
        tintColor = [UIColor dw_darkTitleColor];
    }
    else {
        // received
        dashAmount = received;
        tintColor = [UIColor dw_dashBlueColor];
    }

    self.dashAmount = dashAmount;
    self.dashAmountTintColor = tintColor;

    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    NSString *fiatAmount = [priceManager localCurrencyStringForDashAmount:dashAmount];

    self.addressLabel.text = address;
    self.dateLabel.text = [self.dataProvider dateForTransaction:transaction];
    self.fiatAmountLabel.text = fiatAmount;

    [self updateDashAmountLabelWithDashAmount:dashAmount tintColor:tintColor];
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification:(NSNotification *)notification {
    [self updateDashAmountLabelWithDashAmount:self.dashAmount tintColor:self.dashAmountTintColor];
}

#pragma mark - Private

- (void)updateDashAmountLabelWithDashAmount:(uint64_t)dashAmount tintColor:(UIColor *)tintColor {
    NSParameterAssert(self.dataProvider);

    UIFont *font = [UIFont dw_fontForTextStyle:UIFontTextStyleCaption1];

    self.dashAmountLabel.attributedText = [self.dataProvider stringForDashAmount:dashAmount
                                                                       tintColor:tintColor
                                                                            font:font];
}

@end

NS_ASSUME_NONNULL_END
