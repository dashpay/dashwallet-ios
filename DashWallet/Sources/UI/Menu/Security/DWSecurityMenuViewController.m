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

#import "DWFormTableViewController.h"
#import "DWSecurityMenuModel.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSecurityMenuViewController ()

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

            // TODO: impl
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

    DWFormTableViewController *formController = [[DWFormTableViewController alloc] initWithStyle:UITableViewStylePlain];
    [formController setSections:[self sections] placeholderText:nil];

    [self addChildViewController:formController];
    formController.view.frame = self.view.bounds;
    formController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:formController.view];
    [formController didMoveToParentViewController:self];
    self.formController = formController;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - Private

- (void)updateBiometricAuthCellModel {
    self.biometricAuthCellModel.subTitle = self.model.biometricAuthSpendingLimit;
}

@end

NS_ASSUME_NONNULL_END
