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

#import "DWDerivationPathKeysViewController.h"

#import <DashSync/DashSync.h>

#import "DWDerivationPathKeysModel.h"
#import "DWDerivationPathKeysTableViewCell.h"
#import "DWSelectorFormTableViewCell.h"
#import "DWUIKit.h"
#import "UIView+DWHUD.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWDerivationPathKeysViewController ()

@property (readonly, nonatomic, strong) DWDerivationPathKeysModel *model;
@property (nonatomic, assign) NSInteger visibleIndexes;

@end

@implementation DWDerivationPathKeysViewController

- (instancetype)initWithDerivationPath:(DSAuthenticationKeysDerivationPath *)derivationPath {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _model = [[DWDerivationPathKeysModel alloc] initWithDerivationPath:derivationPath];
        self.derivationPath = derivationPath;
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.tableFooterView = [[UIView alloc] init];
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionHeaderHeight = 30.0;

    NSArray<Class> *cellClasses = @[
        DWSelectorFormTableViewCell.class,
        DWDerivationPathKeysTableViewCell.class,
    ];

    for (Class cellClass in cellClasses) {
        [self.tableView registerClass:cellClass forCellReuseIdentifier:NSStringFromClass(cellClass)];
    }

    self.visibleIndexes = [self.derivationPath firstUnusedIndex] + 1;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.visibleIndexes + 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == self.visibleIndexes) {
        return 1;
    }
    else {
        return _DWDerivationPathInfo_Count;
    }
}

- (nullable UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UITextView *labelTextView = [[UITextView alloc] initWithFrame:CGRectZero];
    labelTextView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
    labelTextView.textColor = [UIColor dw_darkTitleColor];
    labelTextView.userInteractionEnabled = FALSE;
    labelTextView.font = [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
    labelTextView.adjustsFontForContentSizeCategory = YES;
    labelTextView.textAlignment = NSTextAlignmentCenter;
    labelTextView.textContainerInset = UIEdgeInsetsMake(10, 0, 10, 0);
    if (section == self.visibleIndexes) {
        labelTextView.text = @" ";
    }
    else {
        labelTextView.text = [NSString stringWithFormat:NSLocalizedString(@"Keypair %ld", nil), section];
    }
    return labelTextView;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == self.visibleIndexes) {
        NSString *cellId = DWSelectorFormTableViewCell.dw_reuseIdentifier;
        DWSelectorFormTableViewCell *cell = (DWSelectorFormTableViewCell *)[tableView dequeueReusableCellWithIdentifier:cellId forIndexPath:indexPath];
        cell.cellModel = self.model.loadMoreItem;
        return cell;
    }
    else {
        NSString *cellId = DWDerivationPathKeysTableViewCell.dw_reuseIdentifier;
        DWDerivationPathKeysTableViewCell *cell =
            (DWDerivationPathKeysTableViewCell *)[tableView dequeueReusableCellWithIdentifier:cellId
                                                                                 forIndexPath:indexPath];

        NSInteger index = indexPath.section;
        DWDerivationPathInfo info = indexPath.row;
        id<DWDerivationPathKeysItem> item = [self.model itemForInfo:info atIndex:index];
        cell.item = item;

        return cell;
    }
}

#pragma mark - UITableViewDataDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == self.visibleIndexes) {
        self.visibleIndexes += 1;

        [tableView beginUpdates];
        [tableView insertSections:[NSIndexSet indexSetWithIndex:self.visibleIndexes - 1] withRowAnimation:UITableViewRowAnimationAutomatic];
        [tableView endUpdates];

        [tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:self.visibleIndexes - 1] atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
    }
    else {
        DWDerivationPathKeysTableViewCell *cell =
            (DWDerivationPathKeysTableViewCell *)[tableView cellForRowAtIndexPath:indexPath];
        id<DWDerivationPathKeysItem> item = cell.item;
        [UIPasteboard generalPasteboard].string = item.detail;

        [self.view dw_showInfoHUDWithText:NSLocalizedString(@"Copied", nil)];
    }
}

@end

NS_ASSUME_NONNULL_END
