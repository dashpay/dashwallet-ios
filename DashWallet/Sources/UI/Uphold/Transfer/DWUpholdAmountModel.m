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

#import "DWUpholdAmountModel.h"

#import "DWAmountModel+DWProtected.h"
#import "DWEnvironment.h"
#import "DWUpholdCardObject.h"
#import "NSAttributedString+DWBuilder.h"
#import "UIColor+DWStyle.h"
#import "UIFont+DWFont.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUpholdAmountModel ()

@property (readonly, strong, nonatomic) DWUpholdCardObject *card;
@property (null_resettable, nonatomic, strong) DWAmountDescriptionViewModel *availableDescriptionModel;
@property (null_resettable, nonatomic, strong) DWAmountDescriptionViewModel *insufficientFundsDescriptionModel;

@end

NS_ASSUME_NONNULL_END

@implementation DWUpholdAmountModel

- (instancetype)initWithCard:(DWUpholdCardObject *)card {
    self = [super init];
    if (self) {
        _card = card;

        self.descriptionModel = self.availableDescriptionModel;
    }
    return self;
}

- (BOOL)showsMaxButton {
    return YES;
}

- (BOOL)amountIsValidForProceeding {
    BOOL superResult = [super amountIsValidForProceeding];
    if (!superResult) {
        return NO;
    }

    return [self isSufficientDashForInput];
}

- (void)selectAllFundsWithPreparationBlock:(void (^)(void))preparationBlock {
    NSParameterAssert(self.card);
    if (self.card == nil) {
        return;
    }

    preparationBlock();

    NSDecimalNumber *duffs = (NSDecimalNumber *)[NSDecimalNumber numberWithLongLong:DUFFS];
    uint64_t allAvailableFunds = [self.card.available decimalNumberByMultiplyingBy:duffs].longLongValue;

    if (allAvailableFunds > 0) {
        self.amountEnteredInDash = [[DWAmountObject alloc] initWithPlainAmount:allAvailableFunds];
        self.amountEnteredInLocalCurrency = nil;
        [self updateCurrentAmount];
    }
}

- (void)updateCurrentAmount {
    [super updateCurrentAmount];

    if (self.card == nil) {
        // initialization in progress
        return;
    }

    if ([self isSufficientDashForInput]) {
        self.descriptionModel = self.availableDescriptionModel;
    }
    else {
        self.descriptionModel = self.insufficientFundsDescriptionModel;
    }
}

- (void)resetAttributedValues {
    _availableDescriptionModel = nil;
    _insufficientFundsDescriptionModel = nil;
}

#pragma mark - Private

- (BOOL)isSufficientDashForInput {
    NSDecimalNumber *decimalDash = [self decimalAmountNumber];
    if ([decimalDash compare:self.card.available] == NSOrderedDescending) {
        return NO;
    }

    return YES;
}

- (NSDecimalNumber *)decimalAmountNumber {
    NSDecimalNumber *duffs = (NSDecimalNumber *)[NSDecimalNumber numberWithLongLong:DUFFS];
    NSDecimalNumber *dash = (NSDecimalNumber *)[NSDecimalNumber numberWithLongLong:self.amount.plainAmount];
    NSDecimalNumber *result = [dash decimalNumberByDividingBy:duffs];

    return result;
}

- (DWAmountDescriptionViewModel *)availableDescriptionModel {
    if (_availableDescriptionModel == nil) {
        NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];

        NSDictionary *attributes = @{
            NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleCallout],
            NSForegroundColorAttributeName : [UIColor dw_secondaryTextColor],
        };
        NSAttributedString *description =
            [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Enter the amount to transfer", nil)
                                            attributes:attributes];

        [result beginEditing];
        [result appendAttributedString:description];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
        [result appendAttributedString:[self availableAttributedString]];
        [result endEditing];

        DWAmountDescriptionViewModel *model = [[DWAmountDescriptionViewModel alloc] init];
        model.attributedText = result;

        _availableDescriptionModel = model;
    }

    return _availableDescriptionModel;
}

- (DWAmountDescriptionViewModel *)insufficientFundsDescriptionModel {
    if (_insufficientFundsDescriptionModel == nil) {
        NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];

        NSDictionary *attributes = @{
            NSFontAttributeName : [UIFont dw_fontForTextStyle:UIFontTextStyleCallout],
            NSForegroundColorAttributeName : [UIColor dw_redColor],
        };
        NSAttributedString *description =
            [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Insufficient funds", nil)
                                            attributes:attributes];

        [result beginEditing];
        [result appendAttributedString:description];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
        [result appendAttributedString:[self availableAttributedString]];
        [result endEditing];

        DWAmountDescriptionViewModel *model = [[DWAmountDescriptionViewModel alloc] init];
        model.attributedText = result;

        _insufficientFundsDescriptionModel = model;
    }

    return _insufficientFundsDescriptionModel;
}

- (NSAttributedString *)availableAttributedString {
    NSParameterAssert(self.card);
    if (!self.card) {
        return [[NSAttributedString alloc] init];
    }

    UIColor *color = [UIColor dw_secondaryTextColor];
    UIFont *availableFont = [UIFont dw_fontForTextStyle:UIFontTextStyleFootnote];

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];

    NSString *availableRaw = [self.card.available descriptionWithLocale:[NSLocale currentLocale]];
    NSAttributedString *available =
        [NSAttributedString dw_dashAttributedStringForFormattedAmount:availableRaw
                                                            tintColor:color
                                                                 font:availableFont];

    NSDictionary *attributes = @{
        NSFontAttributeName : availableFont,
        NSForegroundColorAttributeName : color,
    };
    NSAttributedString *suffix =
        [[NSAttributedString alloc] initWithString:NSLocalizedString(@"available", @"lowercase, ex. 4 Dash available")
                                        attributes:attributes];

    [result beginEditing];
    [result appendAttributedString:available];
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:@" "]];
    [result appendAttributedString:suffix];
    [result endEditing];

    return [result copy];
}

@end
