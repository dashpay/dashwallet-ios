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

#import "DWAmountViewController.h"

#import "DWAmountModel.h"
#import "DWAmountView.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWAmountViewController () <DWAmountViewDelegate>

@property (nullable, nonatomic, strong) DWAmountView *contentView;

@end

@implementation DWAmountViewController

- (instancetype)initWithModel:(DWAmountModel *)model {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _model = model;
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self.contentView viewWillAppear];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self.contentView viewWillDisappear];
}

#pragma mark - DWAmountViewDelegate

- (void)amountView:(DWAmountView *)view setActionButtonEnabled:(BOOL)enabled {
    self.actionButton.enabled = enabled;
}

#pragma mark - Private

- (void)setupView {
    NSParameterAssert(self.model);

    DWAmountView *contentView = [[DWAmountView alloc] initWithModel:self.model];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    contentView.delegate = self;
    [self setupContentView:contentView];
    self.contentView = contentView;
}

- (BOOL)validateInputAmount {
    if ([self.model isEnteredAmountLessThenMinimumOutputAmount]) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:NSLocalizedString(@"Amount too small", nil)
                             message:[NSString stringWithFormat:NSLocalizedString(@"Dash payments can't be less than %@", nil),
                                                                [self.model minimumOutputAmountFormattedString]]
                      preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"OK", nil)
                      style:UIAlertActionStyleCancel
                    handler:nil];
        [alert addAction:okAction];
        [self presentViewController:alert animated:YES completion:nil];

        return NO;
    }

    return YES;
}

@end

NS_ASSUME_NONNULL_END
