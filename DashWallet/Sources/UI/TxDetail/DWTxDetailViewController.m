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

#import "DWTxDetailViewController.h"

#import "DWTxDetailContentView.h"
#import "DWTxDetailModel.h"
#import "SFSafariViewController+DashWallet.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWTxDetailViewController () <DWTxDetailContentViewDelegate>

@property (nonatomic, strong) DWTxDetailContentView *view;
@property (readonly, nonatomic, strong) DWTxDetailModel *model;
@property (readonly, nonatomic, assign) BOOL displayingAsDetails;

@end

@implementation DWTxDetailViewController

@dynamic view;

- (instancetype)initWithTransaction:(DSTransaction *)transaction
                       dataProvider:(id<DWTransactionListDataProviderProtocol>)dataProvider
                displayingAsDetails:(BOOL)displayingAsDetails {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _model = [[DWTxDetailModel alloc] initWithTransaction:transaction dataProvider:dataProvider];
        _displayingAsDetails = displayingAsDetails;
    }
    return self;
}

- (void)loadView {
    const CGRect frame = [UIScreen mainScreen].bounds;
    DWTxDetailContentView *view = [[DWTxDetailContentView alloc] initWithFrame:frame];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    view.delegate = self;
    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    if (self.displayingAsDetails) {
        switch (self.model.direction) {
            case DSTransactionDirection_Moved:
                self.view.displayType = DWTxDetailDisplayType_Moved;
                break;
            case DSTransactionDirection_Sent:
                self.view.displayType = DWTxDetailDisplayType_Sent;
                break;
            case DSTransactionDirection_Received:
                self.view.displayType = DWTxDetailDisplayType_Received;
                break;
            case DSTransactionDirection_NotAccountFunds:
                //in v14 it can only be masternode registration
                self.view.displayType = DWTxDetailDisplayType_MasternodeRegistration;
                break;
            default:
                break;
        }
    }
    else {
        self.view.displayType = DWTxDetailDisplayType_Paid;
    }
    self.view.model = self.model;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.view viewDidAppear];
}

#pragma mark - DWTxDetailContentViewDelegate

- (void)txDetailContentView:(DWTxDetailContentView *)view viewInExplorerButtonAction:(UIButton *)sender {
    NSURL *explorerURL = [self.model explorerURL];
    if (!explorerURL) {
        return; // devnet
    }

    SFSafariViewController *controller = [SFSafariViewController dw_controllerWithURL:explorerURL];
    // The views beneath the presented content are not removed from the view hierarchy when the presentation finishes.
    controller.modalPresentationStyle = UIModalPresentationOverFullScreen;
    controller.modalPresentationCapturesStatusBarAppearance = YES;
    [self presentViewController:controller
                       animated:YES
                     completion:^{
                         [self.view setViewInExplorerButtonCopyHintTitle];
                     }];
}

- (void)txDetailContentView:(DWTxDetailContentView *)view closeButtonAction:(UIButton *)sender {
    [self.delegate txDetailViewController:self closeButtonAction:sender];
}

@end

NS_ASSUME_NONNULL_END
