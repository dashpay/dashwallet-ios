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

#import "DWBackupInfoViewController.h"

#import "DWBackupInfoHeaderView.h"
#import "DWBackupSeedPhraseViewController.h"
#import "DWInfoTextCell.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static UIEdgeInsets const SCROLL_INDICATOR_INSETS = {0.0, 0.0, 0.0, -3.0};

@interface DWBackupInfoViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) DWPreviewSeedPhraseModel *seedPhraseModel;

@property (null_resettable, copy, nonatomic) NSArray<NSString *> *items;

@property (strong, nonatomic) IBOutlet UITableView *tableView;
@property (strong, nonatomic) IBOutlet UIButton *showRecoveryPhraseButton;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *contentBottomConstraint;

@end

@implementation DWBackupInfoViewController

+ (instancetype)controllerWithModel:(DWPreviewSeedPhraseModel *)model {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"BackupInfo" bundle:nil];
    DWBackupInfoViewController *controller = [storyboard instantiateInitialViewController];
    controller.seedPhraseModel = model;

    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];

#if SNAPSHOT
    self.showRecoveryPhraseButton.accessibilityIdentifier = @"show_recovery_button";
#endif /* SNAPSHOT */
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.tableView flashScrollIndicators];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    UIView *headerView = self.tableView.tableHeaderView;
    if (headerView != nil) {
        CGSize size = [headerView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
        if (headerView.frame.size.height != size.height) {
            CGRect frame = headerView.frame;
            frame.size.height = size.height;
            headerView.frame = frame;

            self.tableView.tableHeaderView = headerView;
        }
    }
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    [self.tableView reloadData];
}

#pragma mark - Actions

- (IBAction)showRecoveryPhraseButtonAction:(id)sender {
    DWBackupSeedPhraseViewController *controller =
        [[DWBackupSeedPhraseViewController alloc] initWithModel:self.seedPhraseModel];
    controller.shouldCreateNewWalletOnScreenshot = self.shouldCreateNewWalletOnScreenshot;
    controller.delegate = self.delegate;
    [self.navigationController pushViewController:controller animated:YES];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = DWInfoTextCell.dw_reuseIdentifier;
    DWInfoTextCell *cell = (DWInfoTextCell *)[tableView dequeueReusableCellWithIdentifier:cellId
                                                                             forIndexPath:indexPath];
    NSAssert([cell isKindOfClass:DWInfoTextCell.class], @"Invalid table view configuration - unknown cell");
    cell.text = self.items[indexPath.row];

    return cell;
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification:(NSNotification *)notification {
    [self.tableView reloadData];
}

#pragma mark - Private

- (void)setupView {
    self.title = NSLocalizedString(@"Backup Wallet", @"A noun. Used as a title.");

    NSString *cellId = DWInfoTextCell.dw_reuseIdentifier;
    UINib *nib = [UINib nibWithNibName:cellId bundle:nil];
    NSParameterAssert(nib);
    [self.tableView registerNib:nib forCellReuseIdentifier:cellId];
    self.tableView.scrollIndicatorInsets = SCROLL_INDICATOR_INSETS;

    [self.showRecoveryPhraseButton setTitle:NSLocalizedString(@"Show Recovery Phrase", nil)
                                   forState:UIControlStateNormal];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contentSizeCategoryDidChangeNotification:)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];
}

- (NSArray<NSString *> *)items {
    if (!_items) {
        _items = @[
            NSLocalizedString(@"This recovery phrase is your access to the funds in this wallet.", nil),
            NSLocalizedString(@"We do not store this recovery phrase.", nil),
            NSLocalizedString(@"In case if this device is lost / damaged, in case if the Dash Wallet is uninstalled accidentally from this device, you will need this recovery phrase to access your funds.", nil),
        ];
    }

    return _items;
}

@end

NS_ASSUME_NONNULL_END
