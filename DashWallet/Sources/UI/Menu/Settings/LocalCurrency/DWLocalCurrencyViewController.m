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

#import "DWLocalCurrencyViewController.h"

#import "DWLocalCurrencyContentView.h"
#import "DWLocalCurrencyModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWLocalCurrencyViewController () <DWLocalCurrencyContentViewDelegate>

@property (nonatomic, strong) DWLocalCurrencyContentView *view;

@end

@implementation DWLocalCurrencyViewController

@dynamic view;

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
        self.title = NSLocalizedString(@"Local Currency", nil);
        self.hidesBottomBarWhenPushed = YES;
    }

    return self;
}

- (void)loadView {
    CGRect frame = [UIScreen mainScreen].bounds;
    self.view = [[DWLocalCurrencyContentView alloc] initWithFrame:frame];
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view.delegate = self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.model = [[DWLocalCurrencyModel alloc] init];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - DWLocalCurrencyContentViewDelegate

- (void)localCurrencyContentViewdidSelectCurrencyItem:(DWLocalCurrencyContentView *)view {
    [self.delegate localCurrencyViewControllerDidSelectCurrency:self];
}

@end

NS_ASSUME_NONNULL_END
