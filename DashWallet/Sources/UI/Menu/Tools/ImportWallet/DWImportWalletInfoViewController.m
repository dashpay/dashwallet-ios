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

#import "DWImportWalletInfoViewController.h"

#import "DWInfoTextCell.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static UIEdgeInsets const SCROLL_INDICATOR_INSETS = {0.0, 0.0, 0.0, -3.0};

@interface DWImportWalletInfoViewController () <UITableViewDataSource, UITableViewDelegate>

@property (null_resettable, copy, nonatomic) NSArray<NSString *> *items;

@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UITableView *tableView;
@property (strong, nonatomic) IBOutlet UIButton *scanPrivateKeyButton;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *contentBottomConstraint;

@end

@implementation DWImportWalletInfoViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"ImportWalletInfo" bundle:nil];
    DWImportWalletInfoViewController *controller = [storyboard instantiateInitialViewController];
    controller.hidesBottomBarWhenPushed = YES;

    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
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

- (IBAction)scanPrivatekeyButtonAction:(id)sender {
    [self.delegate importWalletInfoViewControllerScanPrivateKeyAction:self];
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
    self.title = NSLocalizedString(@"Import Private Key", nil);

    self.titleLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleTitle3];
    self.titleLabel.text = NSLocalizedString(@"Scan Private Key", nil);

    NSString *cellId = DWInfoTextCell.dw_reuseIdentifier;
    UINib *nib = [UINib nibWithNibName:cellId bundle:nil];
    NSParameterAssert(nib);
    [self.tableView registerNib:nib forCellReuseIdentifier:cellId];
    self.tableView.scrollIndicatorInsets = SCROLL_INDICATOR_INSETS;

    [self.scanPrivateKeyButton setTitle:NSLocalizedString(@"Scan Private Key", nil)
                               forState:UIControlStateNormal];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contentSizeCategoryDidChangeNotification:)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];
}

- (NSArray<NSString *> *)items {
    if (!_items) {
        _items = @[
            NSLocalizedString(@"You are about to sweep funds from another Dash Wallet.", nil),
            NSLocalizedString(@"This will move all coins from that wallet to your wallet on this device.", nil),
            NSLocalizedString(@"When the transaction is confirmed, the other wallet will be worthless and should not be re-used for safety reasons.", nil),
        ];
    }

    return _items;
}

@end

NS_ASSUME_NONNULL_END
