//  
//  Created by Pavel Tikhonenko
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

#import "DWExploreWhereToSpendViewController.h"
#import "DWExploreWhereToSpendInfoViewController.h"
#import "DWUIKit.h"
#import "DWGlobalOptions.h"
#import "DWExploreGiftCardInfoViewController.h"
#import "DWExploreWhereToSpendItemCell.h"
#import "DWExploreWhereToSpendFiltersCell.h"
#import "DWExploreWhereToSpendSearchCell.h"
#import "DWExploreWhereToSpendSegmentedCell.h"
#import "DWExploreMerchant.h"

@interface DWExploreWhereToSpendViewController () <UITableViewDataSource, UITableViewDelegate>

@property (readonly, nonatomic, strong) UITableView *tableView;
@property (readonly, nonatomic, strong) NSArray<NSString *> *segmentTitles;
@property (nonatomic, strong) NSArray<DWExploreMerchant *> *merchants;
@property (readonly, nonatomic, assign) NSInteger selectedSegmentIdx;

@end

#define DW_EXPLORE_WHERE_TO_SPEND_SECTION_COUNT 4

typedef NS_ENUM(NSUInteger, DWExploreWhereToSpendSections) {
    DWExploreWhereToSpendSectionsSegments,
    DWExploreWhereToSpendSectionsSearch,
    DWExploreWhereToSpendSectionsFilters,
    DWExploreWhereToSpendSectionsItems,
};

@implementation DWExploreWhereToSpendViewController

- (void)infoAction {
    DWExploreGiftCardInfoViewController *vc = [DWExploreGiftCardInfoViewController new];
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)showInfoViewControllerIfNeeded {
    if(![DWGlobalOptions sharedInstance].dashpayExploreWhereToSpendInfoShown) {
        [self showInfoViewController];
        
        [DWGlobalOptions sharedInstance].dashpayExploreWhereToSpendInfoShown = YES;
    }
}

- (void)showInfoViewController {
    DWExploreWhereToSpendInfoViewController *vc = [[DWExploreWhereToSpendInfoViewController alloc] init];
    [self presentViewController:vc animated:YES completion:nil];
}

- (UIBarButtonItem *)cancelBarButton {
    UIButton* infoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
    [infoButton addTarget:self action:@selector(infoAction) forControlEvents:UIControlEventTouchUpInside];
    UIBarButtonItem* infoBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:infoButton];
    return infoBarButtonItem;
}

- (void)configureHierarchy {
    UITableView *tableView = [UITableView new];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.delegate = self;
    tableView.dataSource = self;
    [tableView registerClass:[DWExploreWhereToSpendSegmentedCell class] forCellReuseIdentifier:DWExploreWhereToSpendSegmentedCell.dw_reuseIdentifier];
    [tableView registerClass:[DWExploreWhereToSpendSearchCell class] forCellReuseIdentifier:DWExploreWhereToSpendSearchCell.dw_reuseIdentifier];
    [tableView registerClass:[DWExploreWhereToSpendFiltersCell class] forCellReuseIdentifier:DWExploreWhereToSpendFiltersCell.dw_reuseIdentifier];
    [tableView registerClass:[DWExploreWhereToSpendItemCell class] forCellReuseIdentifier:DWExploreWhereToSpendItemCell.dw_reuseIdentifier];
    [self.view addSubview:tableView];
    _tableView = tableView;
    
    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    [self showInfoViewControllerIfNeeded];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.merchants = [DWExploreMerchant mockData];
    
    self.title = NSLocalizedString(@"Where to Spend", nil);
    
    _segmentTitles = @[NSLocalizedString(@"Online", nil), NSLocalizedString(@"Nearby", nil), NSLocalizedString(@"All", nil)];
    _selectedSegmentIdx = 0;
    
    self.view.backgroundColor = [UIColor dw_backgroundColor];
    
    self.navigationItem.rightBarButtonItem = [self cancelBarButton];
    
    [self configureHierarchy];
}

- (nonnull UITableViewCell *)tableView:(nonnull UITableView *)tableView cellForRowAtIndexPath:(nonnull NSIndexPath *)indexPath {
    UITableViewCell *cell;
    switch(indexPath.section) {
        case DWExploreWhereToSpendSectionsSegments:
        {
            DWExploreWhereToSpendSegmentedCell *segmentsCell = [tableView dequeueReusableCellWithIdentifier:DWExploreWhereToSpendSegmentedCell.dw_reuseIdentifier forIndexPath:indexPath];
            segmentsCell.separatorInset = UIEdgeInsetsMake(0, 2000, 0, 0);
            cell = segmentsCell;
            break;
        }
        case DWExploreWhereToSpendSectionsSearch:
        {
            DWExploreWhereToSpendSearchCell *searchCell = [tableView dequeueReusableCellWithIdentifier:DWExploreWhereToSpendSearchCell.dw_reuseIdentifier forIndexPath:indexPath];
            searchCell.separatorInset = UIEdgeInsetsMake(0, 2000, 0, 0);
            cell = searchCell;
            break;
        }
        case DWExploreWhereToSpendSectionsFilters:
        {
            DWExploreWhereToSpendFiltersCell *filterCell = [tableView dequeueReusableCellWithIdentifier:DWExploreWhereToSpendFiltersCell.dw_reuseIdentifier forIndexPath:indexPath];
            filterCell.title = _segmentTitles[_selectedSegmentIdx];
            cell = filterCell;
            break;
        }
        case DWExploreWhereToSpendSectionsItems:
        {
            DWExploreMerchant *merchant = self.merchants[indexPath.row];
            DWExploreWhereToSpendItemCell *itemCell = [tableView dequeueReusableCellWithIdentifier:DWExploreWhereToSpendItemCell.dw_reuseIdentifier forIndexPath:indexPath];
            [itemCell updateWithMerchant:merchant];
            cell = itemCell;
            break;
        }
    }
    
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
    
}

- (NSInteger)tableView:(nonnull UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if(section == DWExploreWhereToSpendSectionsItems) {
        return self.merchants.count;
    }
    
    return 1;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return DW_EXPLORE_WHERE_TO_SPEND_SECTION_COUNT;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch(indexPath.section) {
        case DWExploreWhereToSpendSectionsSegments:
            return 62.0f;
            break;
        case DWExploreWhereToSpendSectionsSearch:
            return 60.0f;
            break;
        case DWExploreWhereToSpendSectionsFilters:
            return 50.0f;
            break;
        case DWExploreWhereToSpendSectionsItems:
            return 56.0f;
            break;
    }
    
    return 0.0f;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
}
@end





