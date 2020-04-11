//
//  Created by Sam Westrich
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

#import "DWLocalMasternodeControlViewController.h"

#import "DWEnvironment.h"
#import "DWFormTableViewController.h"
#import "DWKeyValueFormTableViewCell.h"
#import "DWPublicKeyGenerationTableViewCell.h"
#import "DWSignPayloadModel.h"
#import "DWSignPayloadViewController.h"
#import "DWUIKit.h"
#import <DashSync/DashSync.h>

#define INPUT_CELL_HEIGHT 75
#define PUBLIC_KEY_CELL_HEIGHT 150

typedef NS_ENUM(NSUInteger, DWMasternodeControlCell) {
    DWMasternodeControlCell_Name,
    DWMasternodeControlCell_CollateralInfo,
    DWMasternodeControlCell_Host,
    DWMasternodeControlCell_PayoutAddress,
    DWMasternodeControlCell_OwnerKey,
    DWMasternodeControlCell_OperatorKey,
    DWMasternodeControlCell_VotingKey,
    _DWMasternodeControlCell_Count,
};

typedef NS_ENUM(NSUInteger, DWMasternodeActionCell) {
    DWMasternodeActionCell_SignMessage,
    DWMasternodeActionCell_UpdateHost,
    DWMasternodeActionCell_ChangePayoutAddress,
    DWMasternodeActionCell_ChangeOperator,
    DWMasternodeActionCell_ChangeVotingKey,
    _DWMasternodeActionCell_Count,
};

@interface DWLocalMasternodeControlViewController ()

@property (nonatomic, strong) DWActionFormCellModel *registerActionModel;
@property (nonatomic, strong) DWFormTableViewController *formController;
@property (nonatomic, strong) DSLocalMasternode *localMasternode;

@end

@implementation DWLocalMasternodeControlViewController

- (instancetype)initWithLocalMasternode:(DSLocalMasternode *)localMasternode {
    if (self = [super initWithNibName:nil bundle:nil]) {
        self.title = NSLocalizedString(@"Control", nil);
        self.hidesBottomBarWhenPushed = YES;
        _localMasternode = localMasternode;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

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

#pragma mark - Data Source

- (NSString *)titleForCellAtRow:(NSUInteger)row {
    switch (row) {
        case DWMasternodeControlCell_Name:
            return NSLocalizedString(@"Local Name", nil);
        case DWMasternodeControlCell_CollateralInfo:
            return NSLocalizedString(@"Collateral Information", nil);
        case DWMasternodeControlCell_Host:
            return NSLocalizedString(@"Host", nil);
        case DWMasternodeControlCell_PayoutAddress:
            return NSLocalizedString(@"Payout Address", nil);
        case DWMasternodeControlCell_OwnerKey:
            return NSLocalizedString(@"Owner Private Key", nil);
        case DWMasternodeControlCell_OperatorKey:
            return NSLocalizedString(@"Operator Public Key", nil);
        case DWMasternodeControlCell_VotingKey:
            return NSLocalizedString(@"Voting Public Key", nil);
    }
    return @"";
}

- (NSString *)placeholderForCellAtRow:(NSUInteger)row {
    switch (row) {
        case DWMasternodeControlCell_Name:
            return NSLocalizedString(@"Enter a Nickname for this Masternode", nil);
        case DWMasternodeControlCell_CollateralInfo:
            return NSLocalizedString(@"No Collateral Information", nil);
        case DWMasternodeControlCell_PayoutAddress:
            return NSLocalizedString(@"Unknown Payout Address", nil);
        case DWMasternodeControlCell_OwnerKey:
            return NSLocalizedString(@"Unknown Owner Private Key", nil);
        case DWMasternodeControlCell_OperatorKey:
            return NSLocalizedString(@"Unknown Operator Public Key", nil);
        case DWMasternodeControlCell_VotingKey:
            return NSLocalizedString(@"Unknown Voting Public Key", nil);
    }
    return @"";
}

- (NSString *)actionForCellAtRow:(NSUInteger)row {
    switch (row) {
        case DWMasternodeControlCell_CollateralInfo:
            return NSLocalizedString(@"Lookup", nil);
        case DWMasternodeControlCell_PayoutAddress:
            return NSLocalizedString(@"Lookup", nil);
        case DWMasternodeControlCell_OwnerKey:
            return NSLocalizedString(@"Lookup", nil);
        case DWMasternodeControlCell_OperatorKey:
            return NSLocalizedString(@"Lookup", nil);
        case DWMasternodeControlCell_VotingKey:
            return NSLocalizedString(@"Lookup", nil);
        default:
            return nil;
    }
}

- (NSString *)actionTitleForCellAtRow:(NSUInteger)row {
    switch (row) {
        case DWMasternodeActionCell_SignMessage:
            return NSLocalizedString(@"Sign Message", nil);
        case DWMasternodeActionCell_UpdateHost:
            return NSLocalizedString(@"Update Host", nil);
        case DWMasternodeActionCell_ChangeOperator:
            return NSLocalizedString(@"Change Operator", nil);
        case DWMasternodeActionCell_ChangeVotingKey:
            return NSLocalizedString(@"Change Voting Key", nil);
        case DWMasternodeActionCell_ChangePayoutAddress:
            return NSLocalizedString(@"Change Payout Address", nil);
    }
    return @"";
}

- (BOOL)resignCellsFirstResponders {
    BOOL resigned = FALSE;
    for (UITableViewCell *cell in self.formController.tableView.visibleCells) {
        resigned |= [cell resignFirstResponder];
    }
    return resigned;
}

- (void (^)(void))actionBlockForModel:(DWKeyValueFormCellModel *)model forCellAtRow:(NSUInteger)row {
    __weak __typeof(self) weakSelf = self;
    __weak __typeof(model) weakModel = model;
    switch (row) {
        case DWMasternodeControlCell_CollateralInfo:
            return ^{
                __strong __typeof(weakSelf) strongSelf = weakSelf;

                if (!strongSelf) {
                    return;
                }
            };
        case DWMasternodeControlCell_Host:
            return ^{
                __strong __typeof(weakModel) strongModel = weakModel;
                if (!strongModel) {
                    return;
                }
                strongModel.valueText = [NSString stringWithFormat:@"%d", [DWEnvironment sharedInstance].currentChain.standardPort];
            };
        case DWMasternodeControlCell_PayoutAddress:
            return ^{
                __strong __typeof(weakModel) strongModel = weakModel;
                if (!strongModel) {
                    return;
                }
            };
        case DWMasternodeControlCell_OwnerKey:
            return ^{
                __strong __typeof(weakModel) strongModel = weakModel;
                if (!strongModel) {
                    return;
                }
            };
        case DWMasternodeControlCell_OperatorKey:
            return ^{
                __strong __typeof(weakModel) strongModel = weakModel;
                if (!strongModel) {
                    return;
                }
            };
        case DWMasternodeControlCell_VotingKey:
            return ^{
                __strong __typeof(weakModel) strongModel = weakModel;
                if (!strongModel) {
                    return;
                }
            };
        default:
            return nil;
    }
}

- (DWBaseFormCellModel *)modelForRow:(NSUInteger)row {
    NSString *actionText = [self actionForCellAtRow:row];
    DWKeyValueFormCellModel *model = [[DWKeyValueFormCellModel alloc] initWithTitle:[self titleForCellAtRow:row] valueText:@"" placeholderText:[self placeholderForCellAtRow:row] actionText:actionText ? [[NSAttributedString alloc] initWithString:actionText] : nil];
    if (actionText) {
        model.actionBlock = [self actionBlockForModel:model forCellAtRow:row];
    }
    __weak __typeof(self.localMasternode) weakModel = self.localMasternode;
    switch (row) {
        case DWMasternodeControlCell_Name: {
            model.valueText = self.localMasternode.name;
            [model mvvm_observe:DW_KEYPATH(model, valueText)
                           with:^(__typeof(self) self, NSString *value) {
                               __strong __typeof(weakModel) strongModel = weakModel;
                               if (!strongModel) {
                                   return;
                               }
                               [strongModel registerName:value];
                           }];
            break;
        }
        case DWMasternodeControlCell_CollateralInfo: {
            model.valueText = @"";
            model.editable = FALSE;
            break;
        }
        case DWMasternodeControlCell_Host: {
            model.valueText = self.localMasternode.ipAddressAndPortString;
            model.editable = FALSE;
            break;
        }
        case DWMasternodeControlCell_PayoutAddress: {
            model.valueText = self.localMasternode.payoutAddress;
            model.editable = FALSE;
            break;
        }
        case DWMasternodeControlCell_OwnerKey: {
            model.valueText = self.localMasternode.ownerPublicKeyData.hexString;
            model.editable = FALSE;
            break;
        }
        case DWMasternodeControlCell_OperatorKey: {
            model.valueText = self.localMasternode.operatorPublicKeyData.hexString;
            model.editable = FALSE;
            break;
        }
        case DWMasternodeControlCell_VotingKey: {
            model.valueText = self.localMasternode.votingPublicKeyData.hexString;
            model.editable = FALSE;
            break;
        }
    }

    return model;
}

- (NSArray<DWBaseFormCellModel *> *)items {
    NSMutableArray<DWBaseFormCellModel *> *items = [NSMutableArray array];

    for (NSUInteger i = 0; i < _DWMasternodeControlCell_Count; i++) {
        [items addObject:[self modelForRow:i]];
    }

    return items;
}

- (DWBaseFormCellModel *)actionModelAtIndex:(NSUInteger)index {
    __weak typeof(self) weakSelf = self;
    DWActionFormCellModel *actionModel = [[DWActionFormCellModel alloc] initWithTitle:[self actionTitleForCellAtRow:index]];
    actionModel.didSelectBlock = ^(DWActionFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        [strongSelf resignCellsFirstResponders];
    };
    return actionModel;
}

- (NSArray<DWBaseFormCellModel *> *)actionItems {
    NSMutableArray<DWBaseFormCellModel *> *items = [NSMutableArray array];

    for (NSUInteger i = 0; i < _DWMasternodeActionCell_Count; i++) {
        [items addObject:[self actionModelAtIndex:i]];
    }

    return items;
}

- (DWBaseFormCellModel *)registerActionModel {
    __weak typeof(self) weakSelf = self;
    DWActionFormCellModel *registerModel = [[DWActionFormCellModel alloc] initWithTitle:NSLocalizedString(@"View Signing Info", nil)];
    registerModel.didSelectBlock = ^(DWActionFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        [strongSelf resignCellsFirstResponders];

        //        [self.model findCollateralTransactionWithCompletion:^(NSError *_Nonnull error) {
        //            if (error) {
        //                return;
        //            }
        //            [self.model registerMasternode:self
        //                    requestsPayloadSigning:^{
        //                        [self showPayloadSigning];
        //                    }
        //                                completion:^(NSError *_Nonnull error){
        //
        //                                }];
        //            [self showPayloadSigning];
        //        }];
    };
    self.registerActionModel = registerModel;
    return registerModel;
}

- (NSArray<DWFormSectionModel *> *)sections {
    DWFormSectionModel *section = [[DWFormSectionModel alloc] init];
    section.items = [self items];

    DWFormSectionModel *actionsSection = [[DWFormSectionModel alloc] init];
    actionsSection.items = [self actionItems];

    return @[ section, actionsSection ];
}

@end
