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

#import "DWExtendedPublicKeysViewController.h"


#import "DWEnvironment.h"

#import "DWDerivationPathKeysTableViewCell.h"
#import "DWExtendedPublicKeysModel.h"
#import "DWSelectorFormTableViewCell.h"
#import "DWUIKit.h"
#import "UIView+DWHUD.h"


NS_ASSUME_NONNULL_BEGIN

@interface DWExtendedPublicKeysViewController ()

@property (readonly, nonatomic, strong) DWExtendedPublicKeysModel *model;

@end

@implementation DWExtendedPublicKeysViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _model = [[DWExtendedPublicKeysModel alloc] init];

        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = NSLocalizedString(@"Extended Public Keys", nil);

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.tableFooterView = [[UIView alloc] init];

    NSArray<Class> *cellClasses = @[
        DWDerivationPathKeysTableViewCell.class,
    ];

    for (Class cellClass in cellClasses) {
        [self.tableView registerClass:cellClass forCellReuseIdentifier:NSStringFromClass(cellClass)];
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.model.derivationPaths.count;
}

- (nullable UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *view = [[UIView alloc] init];
    return view;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = DWDerivationPathKeysTableViewCell.dw_reuseIdentifier;
    DWDerivationPathKeysTableViewCell *cell =
        (DWDerivationPathKeysTableViewCell *)[tableView dequeueReusableCellWithIdentifier:cellId
                                                                             forIndexPath:indexPath];

    DSDerivationPath *derivationPath = self.model.derivationPaths[indexPath.row];
    id<DWDerivationPathKeysItem> item = [self.model itemFor:derivationPath];
    cell.item = item;

    return cell;
}

#pragma mark - UITableViewDataDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    DWDerivationPathKeysTableViewCell *cell =
        (DWDerivationPathKeysTableViewCell *)[tableView cellForRowAtIndexPath:indexPath];
    id<DWDerivationPathKeysItem> item = cell.item;
    if (item && item.detail && ![item.detail isEqualToString:@""]) {
        [UIPasteboard generalPasteboard].string = item.detail;
        [self.view dw_showInfoHUDWithText:NSLocalizedString(@"Copied", nil)];
    }
}

@end

NS_ASSUME_NONNULL_END
