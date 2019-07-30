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

#import "DWFormTableViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWLocalCurrecnySelectorViewController ()

@property (nonatomic, strong) UILabel *priceSourceLabel;

@end

@implementation DWLocalCurrecnySelectorViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    CGFloat height = 160.0;
    CGRect frame = CGRectMake(0.0, -height, CGRectGetWidth([UIScreen mainScreen].bounds), height);
    UILabel *priceSourceLabel = [[UILabel alloc] initWithFrame:frame];
    priceSourceLabel.textColor = [UIColor darkTextColor];
    priceSourceLabel.font = [UIFont systemFontOfSize:15.0];
    priceSourceLabel.numberOfLines = 0;
    priceSourceLabel.lineBreakMode = NSLineBreakByWordWrapping;
    priceSourceLabel.textAlignment = NSTextAlignmentCenter;
    [self.formController.tableView addSubview:priceSourceLabel];
    self.priceSourceLabel = priceSourceLabel;

    [self walletBalanceDidChangeNotification:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(walletBalanceDidChangeNotification:)
                                                 name:DSWalletBalanceDidChangeNotification
                                               object:nil];
}

- (void)walletBalanceDidChangeNotification:(nullable NSNotification *)sender {
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    self.title = [NSString stringWithFormat:@"1 DASH = %@",
                                            [priceManager localCurrencyStringForDashAmount:DUFFS]];
    self.priceSourceLabel.text = [NSString stringWithFormat:@"📈 %@",
                                  priceManager.lastPriceSourceInfo ?: @"?"];
}

@end

NS_ASSUME_NONNULL_END
