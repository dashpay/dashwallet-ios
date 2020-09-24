//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWEditProfileViewController.h"

#import "DWEditProfileTextFieldCell.h"
#import "DWEditProfileTextViewCell.h"
#import "DWEnvironment.h"
#import "DWProfileAboutCellModel.h"
#import "DWProfileDisplayNameCellModel.h"
#import "DWSharedUIConstants.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWEditProfileViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nullable, nonatomic, strong) DSBlockchainIdentity *blockchainIdentity;

@property (nullable, nonatomic, strong) UITableView *tableView;

@property (nullable, nonatomic, copy) NSArray<DWBaseFormCellModel *> *items;
@property (nullable, nonatomic, strong) DWProfileDisplayNameCellModel *displayNameModel;
@property (nullable, nonatomic, strong) DWProfileAboutCellModel *aboutModel;

@end

NS_ASSUME_NONNULL_END

@implementation DWEditProfileViewController

- (NSString *)actionButtonTitle {
    return NSLocalizedString(@"Save", nil);
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = NSLocalizedString(@"Edit Profile", nil);
    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    self.actionButton.enabled = YES;

    self.blockchainIdentity = [DWEnvironment sharedInstance].currentWallet.defaultBlockchainIdentity;
    NSParameterAssert(self.blockchainIdentity);

    UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                            target:self
                                                                            action:@selector(cancelButtonAction)];
    self.navigationItem.leftBarButtonItem = cancel;

    [self setupItems];
    [self setupView];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - Actions

- (void)cancelButtonAction {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)actionButtonAction:(id)sender {
    [self.blockchainIdentity updateDashpayProfileWithDisplayName:self.displayNameModel.text publicMessage:self.aboutModel.text avatarURLString:@""];

    [self showActivityIndicator];
    __weak typeof(self) weakSelf = self;
    [self.blockchainIdentity signAndPublishProfileWithCompletion:^(BOOL success, BOOL cancelled, NSError *_Nonnull error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        [strongSelf hideActivityIndicator];
        if (success) {
            [strongSelf.delegate editProfileViewControllerDidUpdateUserProfile];
            [strongSelf dismissViewControllerAnimated:YES completion:nil];
        }
    }];
}

#pragma mark - Private

- (void)setupView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.tableFooterView = [[UIView alloc] init];
    self.tableView.contentInset = UIEdgeInsetsMake(DWDefaultMargin(), 0.0, 0.0, 0.0);
    [self setupContentView:self.tableView];

    NSArray<Class> *cellClasses = @[
        DWEditProfileTextViewCell.class,
        DWEditProfileTextFieldCell.class,
    ];
    for (Class cellClass in cellClasses) {
        [self.tableView registerClass:cellClass forCellReuseIdentifier:NSStringFromClass(cellClass)];
    }
}

- (void)setupItems {
    NSMutableArray<DWBaseFormCellModel *> *items = [NSMutableArray array];

    {
        DWProfileDisplayNameCellModel *cellModel = [[DWProfileDisplayNameCellModel alloc] initWithTitle:NSLocalizedString(@"Display Name", nil)];
        self.displayNameModel = cellModel;
        cellModel.autocorrectionType = UITextAutocorrectionTypeNo;
        cellModel.returnKeyType = UIReturnKeyNext;
        cellModel.text = self.blockchainIdentity.matchingDashpayUserInViewContext.displayName;
        [items addObject:cellModel];
    }

    {
        DWProfileAboutCellModel *cellModel = [[DWProfileAboutCellModel alloc] initWithTitle:NSLocalizedString(@"About me", nil)];
        self.aboutModel = cellModel;
        cellModel.text = self.blockchainIdentity.matchingDashpayUserInViewContext.publicMessage;
        [items addObject:cellModel];
    }

    self.items = items;
}

#pragma mark - UITableView

- (NSInteger)tableView:(nonnull UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DWBaseFormCellModel *cellModel = self.items[indexPath.row];

    if ([cellModel isKindOfClass:DWTextViewFormCellModel.class]) {
        NSString *cellId = NSStringFromClass(DWEditProfileTextViewCell.class);
        DWEditProfileTextViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId
                                                                          forIndexPath:indexPath];
        cell.cellModel = (DWTextViewFormCellModel *)cellModel;
        return cell;
    }
    else if ([cellModel isKindOfClass:DWTextFieldFormCellModel.class]) {
        NSString *cellId = NSStringFromClass(DWEditProfileTextFieldCell.class);
        DWEditProfileTextFieldCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId
                                                                           forIndexPath:indexPath];
        cell.cellModel = (DWTextFieldFormCellModel *)cellModel;
        return cell;
    }
    else {
        NSAssert(NO, @"Unknown cell model %@", cellModel);
        return [UITableViewCell new];
    }
}

- (nullable UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *view = [[UIView alloc] init];
    return view;
}

@end
