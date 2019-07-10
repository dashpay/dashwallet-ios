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

#import "DWBackupInfoCell.h"
#import "DWBackupInfoHeaderView.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const CELL_ID = @"DWBackupInfoCell";

@interface DWBackupInfoViewController () <UITableViewDataSource, UITableViewDelegate>

@property (null_resettable, copy, nonatomic) NSArray<NSString *> *items;

@property (strong, nonatomic) IBOutlet UITableView *tableView;
@property (strong, nonatomic) IBOutlet UIButton *showRecoveryPhraseButton;

@end

@implementation DWBackupInfoViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"BackupInfo" bundle:nil];
    return [storyboard instantiateInitialViewController];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
}

#pragma mark - Actions

- (IBAction)showRecoveryPhraseButtonAction:(id)sender {
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DWBackupInfoCell *cell = (DWBackupInfoCell *)[tableView dequeueReusableCellWithIdentifier:CELL_ID
                                                                                 forIndexPath:indexPath];
    NSAssert([cell isKindOfClass:DWBackupInfoCell.class], @"Invalid table view configuration - unknown cell");
    cell.text = self.items[indexPath.row];

    return cell;
}

#pragma mark - UITableViewDelegate

- (nullable UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return [[DWBackupInfoHeaderView alloc] init];
}

#pragma mark - Notifications

- (void)contentSizeCategoryDidChangeNotification:(NSNotification *)notification {
    [self.tableView reloadData];
}

#pragma mark - Private

- (void)setupView {
    UINib *nib = [UINib nibWithNibName:CELL_ID bundle:nil];
    NSParameterAssert(nib);
    [self.tableView registerNib:nib forCellReuseIdentifier:CELL_ID];

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
            NSLocalizedString(@"Incase if this device is lost / damaged, incase if the dash wallet is uninstalled accidently from this device, you will need this recovery phrase to access your funds.", nil),
        ];
    }

    return _items;
}

@end

NS_ASSUME_NONNULL_END
