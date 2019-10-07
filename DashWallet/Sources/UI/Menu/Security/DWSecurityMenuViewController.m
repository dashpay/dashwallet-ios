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

#import "DWSecurityMenuViewController.h"

#import "DWBorderedActionButton.h"
#import "DWFormTableViewController.h"
#import "DWNavigationController.h"
#import "DWSecurityMenuModel.h"
#import "DWSetPinViewController.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSecurityMenuViewController () <DWSetPinViewControllerDelegate>

@property (null_resettable, nonatomic, strong) DWSecurityMenuModel *model;
@property (nonatomic, strong) DWFormTableViewController *formController;
@property (nonatomic, strong) DWSelectorFormCellModel *biometricAuthCellModel;

@end

@implementation DWSecurityMenuViewController

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
        self.title = NSLocalizedString(@"Security", nil);
        self.hidesBottomBarWhenPushed = YES;
    }

    return self;
}

- (DWSecurityMenuModel *)model {
    if (!_model) {
        _model = [[DWSecurityMenuModel alloc] init];
    }

    return _model;
}

- (NSArray<DWBaseFormCellModel *> *)items {
    __weak typeof(self) weakSelf = self;

    NSMutableArray<DWBaseFormCellModel *> *items = [NSMutableArray array];

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"View Recovery Phrase", nil)];
        cellModel.accessoryType = DWSelectorFormAccessoryType_DisclosureIndicator;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            // TODO: impl
        };
        [items addObject:cellModel];
    }

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"Change PIN", nil)];
        cellModel.accessoryType = DWSelectorFormAccessoryType_DisclosureIndicator;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf changePinAction];
        };
        [items addObject:cellModel];
    }

    if (self.model.hasTouchID || self.model.hasFaceID) {
        NSString *title = self.model.hasTouchID ? NSLocalizedString(@"Touch ID limit", nil) : NSLocalizedString(@"Face ID limit", nil);
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:title];
        cellModel.accessoryType = DWSelectorFormAccessoryType_DisclosureIndicator;
        self.biometricAuthCellModel = cellModel;
        [self updateBiometricAuthCellModel];
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            // TODO: impl
        };
        [items addObject:cellModel];
    }

    return items;
}

- (NSArray<DWFormSectionModel *> *)sections {
    DWFormSectionModel *section = [[DWFormSectionModel alloc] init];
    section.items = [self items];

    return @[ section ];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    UIView *contentView = self.view;

    UIColor *backgroundColor = [UIColor dw_secondaryBackgroundColor];
    contentView.backgroundColor = backgroundColor;

    UIView *bottomView = [[UIView alloc] initWithFrame:CGRectZero];
    bottomView.translatesAutoresizingMaskIntoConstraints = NO;
    bottomView.backgroundColor = backgroundColor;
    [contentView addSubview:bottomView];

    DWBorderedActionButton *resetWalletButton = [[DWBorderedActionButton alloc] initWithFrame:CGRectZero];
    resetWalletButton.translatesAutoresizingMaskIntoConstraints = NO;
    resetWalletButton.accentColor = [UIColor dw_redColor];
    [resetWalletButton setTitle:NSLocalizedString(@"Reset Wallet", nil) forState:UIControlStateNormal];
    [bottomView addSubview:resetWalletButton];

    const CGFloat padding = 24.0;

    [NSLayoutConstraint activateConstraints:@[
        [bottomView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [bottomView.bottomAnchor constraintEqualToAnchor:contentView.safeAreaLayoutGuide.bottomAnchor],
        [bottomView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],

        [resetWalletButton.topAnchor constraintEqualToAnchor:bottomView.topAnchor
                                                    constant:padding],
        [resetWalletButton.bottomAnchor constraintEqualToAnchor:bottomView.bottomAnchor
                                                       constant:-padding],
        [resetWalletButton.centerXAnchor constraintEqualToAnchor:bottomView.centerXAnchor],
    ]];

    // Forms

    DWFormTableViewController *formController = [[DWFormTableViewController alloc] initWithStyle:UITableViewStylePlain];
    [formController setSections:[self sections] placeholderText:nil];

    [self addChildViewController:formController];

    UIView *formView = formController.view;
    formView.translatesAutoresizingMaskIntoConstraints = NO;

    [contentView addSubview:formView];

    [NSLayoutConstraint activateConstraints:@[
        [formView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [formView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [formView.bottomAnchor constraintEqualToAnchor:bottomView.topAnchor],
        [formView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
    ]];

    [formController didMoveToParentViewController:self];
    self.formController = formController;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - DWSetPinViewControllerDelegate

- (void)setPinViewControllerDidSetPin:(DWSetPinViewController *)controller {
    [controller.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)setPinViewControllerDidCancel:(DWSetPinViewController *)controller {
    [controller.navigationController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Private

- (void)updateBiometricAuthCellModel {
    self.biometricAuthCellModel.subTitle = self.model.biometricAuthSpendingLimit;
}

- (void)changePinAction {
    [self.model changePinContinueBlock:^(BOOL allowed) {
        if (!allowed) {
            return;
        }

        DWSetPinViewController *controller = [DWSetPinViewController controllerWithIntent:DWSetPinIntent_ChangePin];
        controller.delegate = self;
        DWNavigationController *navigationController = [[DWNavigationController alloc] initWithRootViewController:controller];
        navigationController.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:navigationController animated:YES completion:nil];
    }];
}

@end

NS_ASSUME_NONNULL_END
