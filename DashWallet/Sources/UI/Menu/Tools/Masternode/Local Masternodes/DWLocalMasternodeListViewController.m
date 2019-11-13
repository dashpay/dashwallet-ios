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

#import "DWLocalMasternodeListViewController.h"

#import <DashSync/DashSync.h>

#import "DWLocalMasternodeListModel.h"

#import "DWLocalMasternodeTableViewCell.h"
#import "DWSharedUIConstants.h"
#import "DWUIKit.h"
#import "UIView+DWRecursiveSubview.h"


NS_ASSUME_NONNULL_BEGIN

@interface DWLocalMasternodeListViewController () <UISearchBarDelegate, UISearchResultsUpdating>

@property (nonatomic, strong) DWLocalMasternodeListModel *model;

@end

@implementation DWLocalMasternodeListViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.title = NSLocalizedString(@"My Masternodes", nil);
        self.hidesBottomBarWhenPushed = YES;
    }

    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.model = [[DWLocalMasternodeListModel alloc] init];

    [self setupView];
    [self setupSearchController];

    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // show search bar initially, but hide when scrolling
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    self.navigationItem.hidesSearchBarWhenScrolling = YES;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    // hide semi-transparent overlays above UITextField in UISearchBar to achive basic white color
    UISearchController *searchController = self.navigationItem.searchController;
    UISearchBar *searchBar = searchController.searchBar;
    UITextField *searchTextField = (UITextField *)[searchBar dw_findSubviewOfClass:UITextField.class];
    UIView *searchTextFieldBackground = searchTextField.subviews.firstObject;
    [searchTextFieldBackground.subviews makeObjectsPerformSelector:@selector(setHidden:) withObject:@YES];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.model.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = DWLocalMasternodeTableViewCell.dw_reuseIdentifier;
    DWLocalMasternodeTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId forIndexPath:indexPath];

    DSLocalMasternode *item = self.model.items[indexPath.row];
    [cell configureWithModel:item searchQuery:self.model.trimmedQuery];

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    DSLocalMasternode *item = self.model.items[indexPath.row];
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = searchController.searchBar.text ?: @"";
    [self.model filterItemsWithSearchQuery:query];

    [self.tableView reloadData];
}

#pragma mark - UISearchBarDelegate

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark - Private

- (void)setupSearchController {
    self.definesPresentationContext = YES;

    UISearchController *searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    searchController.searchResultsUpdater = self;
    searchController.obscuresBackgroundDuringPresentation = NO;
    self.navigationItem.searchController = searchController;

    UISearchBar *searchBar = searchController.searchBar;
    searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    searchBar.searchBarStyle = UISearchBarStyleMinimal;
    searchBar.delegate = self;
    searchBar.tintColor = [UIColor dw_tintColor];
    searchBar.barTintColor = [UIColor dw_dashNavigationBlueColor];

    UITextField *searchTextField = (UITextField *)[searchBar dw_findSubviewOfClass:UITextField.class];
    searchTextField.tintColor = [UIColor dw_dashNavigationBlueColor];
    searchTextField.textColor = [UIColor dw_darkTitleColor];
    searchTextField.backgroundColor = [UIColor dw_backgroundColor];

    UIView *searchTextFieldBackground = searchTextField.subviews.firstObject;
    searchTextFieldBackground.backgroundColor = [UIColor dw_backgroundColor];
    searchTextFieldBackground.layer.cornerRadius = 10.0;
    searchTextFieldBackground.layer.masksToBounds = YES;
}

- (void)setupView {
    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 74.0;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInset = UIEdgeInsetsMake(DWDefaultMargin(), 0.0, 0.0, 0.0);

    [self.tableView registerClass:DWLocalMasternodeTableViewCell.class
           forCellReuseIdentifier:DWLocalMasternodeTableViewCell.dw_reuseIdentifier];
}

@end

NS_ASSUME_NONNULL_END
