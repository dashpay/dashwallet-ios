//
//  Created by Andrew Podkovyrin
//  Copyright © 2018 Dash Core Group. All rights reserved.
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

#import "DWLocalCurrecnySelectorViewController.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWLocalCurrecnySelectorViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self walletBalanceDidChangeNotification:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(walletBalanceDidChangeNotification:)
                                                 name:DSWalletBalanceDidChangeNotification
                                               object:nil];
}

- (void)walletBalanceDidChangeNotification:(nullable NSNotification *)sender {
    self.title = [NSString stringWithFormat:@"1 DASH = %@",
                                            [[DSPriceManager sharedInstance] localCurrencyStringForDashAmount:DUFFS]];
}

@end

NS_ASSUME_NONNULL_END
