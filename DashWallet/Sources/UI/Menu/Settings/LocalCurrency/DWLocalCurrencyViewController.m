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

#import "DWLocalCurrencyViewController.h"

#import <DashSync/DashSync.h>

#import "DWLocalCurrencyModel.h"

#import "DWLocalCurrencyTableViewCell.h"
#import "DWSharedUIConstants.h"
#import "DWUIKit.h"
#import "UINavigationBar+DWAppearance.h"
#import "UIView+DWRecursiveSubview.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const SECTION_SPACING = 10.0;

@interface DWLocalCurrencyViewController () <UISearchBarDelegate, UISearchResultsUpdating>

@property (nonatomic, assign) DWNavigationAppearance navigationAppearance;
@property (nonatomic, strong) DWLocalCurrencyModel *model;
@property (nonatomic, strong) UILabel *priceSourceLabel;

@end

@implementation DWLocalCurrencyViewController

- (instancetype)initWithNavigationAppearance:(DWNavigationAppearance)navigationAppearance
                                currencyCode:(nullable NSString *)currencyCode {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.navigationAppearance = navigationAppearance;
        if (navigationAppearance == DWNavigationAppearance_Default) {
            self.title = NSLocalizedString(@"Local Currency", nil);
        }
        self.hidesBottomBarWhenPushed = YES;
        self.isGlobal = YES;
        self.model = [[DWLocalCurrencyModel alloc] initWithCurrencyCode:currencyCode];
    }

    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    switch (self.navigationAppearance) {
        case DWNavigationAppearance_Default:
            break;
        case DWNavigationAppearance_White: {
            [self.navigationController.navigationBar dw_configureForWhiteAppearance];

            if (@available(iOS 13.0, *)) {
                UIBarButtonItem *barButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closeButtonAction)];
                self.navigationItem.rightBarButtonItem = barButton;
            }
            else {
                UIBarButtonItem *barButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(closeButtonAction)];
                self.navigationItem.rightBarButtonItem = barButton;
            }

            UILabel *label = [[UILabel alloc] init];
            label.textColor = [UIColor dw_darkTitleColor];
            label.font = [UIFont dw_fontForTextStyle:UIFontTextStyleHeadline];
            label.text = NSLocalizedString(@"Local Currency", nil);
            [label sizeToFit];

            UIBarButtonItem *leftTitleItem = [[UIBarButtonItem alloc] initWithCustomView:label];
            self.navigationItem.leftBarButtonItem = leftTitleItem;

            break;
        }
    }
    [self.navigationController.navigationBar dw_applyStandardAppearance];

    [self setupView];
    [self setupSearchController];

    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // show search bar initially, but hide when scrolling
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    const NSUInteger selectedIndex = self.model.selectedIndex;
    if (selectedIndex != NSNotFound && selectedIndex < self.model.items.count) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:selectedIndex inSection:0];
        [self.tableView scrollToRowAtIndexPath:indexPath
                              atScrollPosition:UITableViewScrollPositionMiddle
                                      animated:NO];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    self.navigationItem.hidesSearchBarWhenScrolling = YES;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    if (self.navigationAppearance == DWNavigationAppearance_Default) {
        // hide semi-transparent overlays above UITextField in UISearchBar to achive basic white color
        UISearchController *searchController = self.navigationItem.searchController;
        UISearchBar *searchBar = searchController.searchBar;
        UITextField *searchTextField = (UITextField *)[searchBar dw_findSubviewOfClass:UITextField.class];
        UIView *searchTextFieldBackground = searchTextField.subviews.firstObject;
        [searchTextFieldBackground.subviews makeObjectsPerformSelector:@selector(setHidden:) withObject:@YES];
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.model.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = DWLocalCurrencyTableViewCell.dw_reuseIdentifier;
    DWLocalCurrencyTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId forIndexPath:indexPath];

    const NSInteger index = indexPath.row;
    id<DWCurrencyItem> item = self.model.items[index];
    const BOOL selected = index == self.model.selectedIndex;
    [cell configureWithModel:item selected:selected searchQuery:self.model.trimmedQuery];

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    const NSInteger index = indexPath.row;
    id<DWCurrencyItem> item = self.model.items[index];
    [self.model selectItem:item shouldChangeGlobalSettings:self.isGlobal];

    [self.tableView reloadRowsAtIndexPaths:self.tableView.indexPathsForVisibleRows
                          withRowAnimation:UITableViewRowAnimationNone];

    if (self.delegate) {
        [self.delegate localCurrencyViewController:self didSelectCurrency:item.code];
    }
    else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (nullable UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return [[UIView alloc] init];
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

- (void)closeButtonAction {
    if (self.delegate) {
        [self.delegate localCurrencyViewControllerDidCancel:self];
    }
    else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

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

    if (self.navigationAppearance == DWNavigationAppearance_Default) {
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
}

- (void)setupView {
    switch (self.navigationAppearance) {
        case DWNavigationAppearance_Default:
            self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];
            self.tableView.contentInset = UIEdgeInsetsMake(DWDefaultMargin(), 0.0, 0.0, 0.0);
            break;
        case DWNavigationAppearance_White:
            self.view.backgroundColor = [UIColor dw_backgroundColor];
            break;
    }

    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 74.0;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorInset = UIEdgeInsetsZero;
    self.tableView.sectionHeaderHeight = SECTION_SPACING;
    self.tableView.tableFooterView = [[UIView alloc] init];

    [self.tableView registerClass:DWLocalCurrencyTableViewCell.class
           forCellReuseIdentifier:DWLocalCurrencyTableViewCell.dw_reuseIdentifier];

    const CGFloat height = 160.0;
    const CGRect frame = CGRectMake(0.0, -height, CGRectGetWidth([UIScreen mainScreen].bounds), height);
    UILabel *priceSourceLabel = [[UILabel alloc] initWithFrame:frame];
    priceSourceLabel.textColor = [UIColor dw_tertiaryTextColor];
    priceSourceLabel.font = [UIFont dw_fontForTextStyle:UIFontTextStyleBody];
    priceSourceLabel.numberOfLines = 0;
    priceSourceLabel.lineBreakMode = NSLineBreakByWordWrapping;
    priceSourceLabel.textAlignment = NSTextAlignmentCenter;
    [self.tableView addSubview:priceSourceLabel];
    self.priceSourceLabel = priceSourceLabel;

    [self walletBalanceDidChangeNotification:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(walletBalanceDidChangeNotification:)
                                                 name:DSWalletBalanceDidChangeNotification
                                               object:nil];
}

- (void)walletBalanceDidChangeNotification:(nullable NSNotification *)sender {
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    self.priceSourceLabel.text = [NSString stringWithFormat:@"📈 %@",
                                                            priceManager.lastPriceSourceInfo ?: @"?"];
}

@end

NS_ASSUME_NONNULL_END
