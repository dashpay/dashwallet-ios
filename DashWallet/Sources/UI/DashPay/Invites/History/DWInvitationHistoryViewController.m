//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

#import "DWInvitationHistoryViewController.h"

#import "DWEnvironment.h"
#import "DWHistoryFilterViewController.h"
#import "DWHistoryHeaderView.h"
#import "DWInvitationHistoryModel.h"
#import "DWInvitationTableViewCell.h"
#import "DWSendInviteFlowController.h"
#import "DWUIKit.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWInvitationHistoryViewController () <DWInvitationHistoryModelDelegate, UITableViewDelegate, UITableViewDataSource, DWHistoryFilterViewControllerDelegate, DWSendInviteFlowControllerDelegate>

@property (nonatomic, strong) DWInvitationHistoryModel *model;
@property (null_resettable, nonatomic, strong) UITableView *tableView;

@end

@interface DWNonFloatingTableView : UITableView

@end

@implementation DWNonFloatingTableView

- (BOOL)allowsHeaderViewsToFloat {
    return NO;
}

@end

NS_ASSUME_NONNULL_END

@implementation DWInvitationHistoryViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = NSLocalizedString(@"Invite", nil);

    self.model = [[DWInvitationHistoryModel alloc] init];
    self.model.delegate = self;

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    [self.view addSubview:self.tableView];
    [NSLayoutConstraint dw_activate:@[
        [self.tableView pinEdges:self.view],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [_tableView reloadData];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)createInvitationAction:(UIControl *)sender {
    DWSendInviteFlowController *controller = [[DWSendInviteFlowController alloc] init];
    controller.delegate = self;
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)optionsButtonAction:(UIControl *)sender {
    DWHistoryFilterViewController *controller = [[DWHistoryFilterViewController alloc] init];
    controller.delegate = self;
    [self presentViewController:controller animated:YES completion:nil];
}

- (UITableView *)tableView {
    if (_tableView == nil) {
        UITableView *tableView = [[DWNonFloatingTableView alloc] initWithFrame:[UIScreen mainScreen].bounds
                                                                         style:UITableViewStylePlain];
        tableView.translatesAutoresizingMaskIntoConstraints = NO;
        tableView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
        tableView.delegate = self;
        tableView.dataSource = self;
        tableView.rowHeight = UITableViewAutomaticDimension;
        tableView.estimatedRowHeight = 74.0;
        tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
        tableView.estimatedSectionHeaderHeight = 100.0;
        [tableView registerClass:DWInvitationTableViewCell.class
            forCellReuseIdentifier:DWInvitationTableViewCell.dw_reuseIdentifier];
        _tableView = tableView;
    }
    return _tableView;
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.model.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DWInvitationTableViewCell *cell = (DWInvitationTableViewCell *)
        [tableView dequeueReusableCellWithIdentifier:DWInvitationTableViewCell.dw_reuseIdentifier
                                        forIndexPath:indexPath];
    id<DWInvitationItem> item = self.model.items[indexPath.row];
    cell.item = item;
    return cell;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    DWHistoryHeaderView *header = [[DWHistoryHeaderView alloc] init];
    [header.createButton addTarget:self action:@selector(createInvitationAction:) forControlEvents:UIControlEventTouchUpInside];
    [header.optionsButton addTarget:self action:@selector(optionsButtonAction:) forControlEvents:UIControlEventTouchUpInside];
    return header;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *myBlockchainIdentity = wallet.defaultBlockchainIdentity;

    id<DWInvitationHistoryItem> item = self.model.items[indexPath.row];
    NSUInteger index = self.model.items.count - indexPath.row;

    __weak typeof(self) weakSelf = self;
    [item.blockchainInvitation
        createInvitationFullLinkFromIdentity:myBlockchainIdentity
                                  completion:^(BOOL cancelled, NSString *_Nonnull invitationFullLink) {
                                      __strong typeof(weakSelf) strongSelf = weakSelf;
                                      if (!strongSelf) {
                                          return;
                                      }

                                      // skip?
                                      if (cancelled == NO && invitationFullLink == nil) {
                                          return;
                                      }

                                      dispatch_async(dispatch_get_main_queue(), ^{
                                          BaseInvitationViewController *controller =
                                              [[BaseInvitationViewController alloc] initWith:item.blockchainInvitation
                                                                                    fullLink:invitationFullLink
                                                                                       index:index];
                                          controller.title = NSLocalizedString(@"Invite", nil);
                                          controller.hidesBottomBarWhenPushed = YES;
                                          controller.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];
                                          [self.navigationController pushViewController:controller animated:YES];
                                      });
                                  }];
}

#pragma mark - DWSendInviteFlowControllerDelegate

- (void)sendInviteFlowControllerDidFinish:(DWSendInviteFlowController *)controller {
    [controller dismissViewControllerAnimated:YES completion:nil];
    [self.model reload];
}

#pragma mark - DWInvitationHistoryModelDelegate

- (void)invitationHistoryModelDidUpdate:(DWInvitationHistoryModel *)model {
    [self.tableView reloadData];
}

#pragma mark - DWHistoryFilterViewControllerDelegate

- (void)historyFilterViewController:(DWHistoryFilterViewController *)controller
                    didSelectFilter:(DWInvitationHistoryFilter)filter {
    [controller dismissViewControllerAnimated:YES completion:nil];
    self.model.filter = filter;
}

@end
