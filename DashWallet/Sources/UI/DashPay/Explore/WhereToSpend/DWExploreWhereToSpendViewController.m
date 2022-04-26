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

@import MapKit;
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
#import "DWExploreWhereToSpendHandlerView.h"
#import "DWExploreWhereToSpendMapView.h"
#import "DWExploreWhereToSpendLocationServicePopup.h"
#import "dashwallet-Swift.h"

#define DW_EXPLORE_WHERE_TO_SPEND_SECTION_COUNT 4

static CGFloat const kHandlerHeight = 24.0f;
static CGFloat const kDefaultOpenedMapPosition = 260.0f;
static CGFloat const kDefaultClosedMapPosition = -kHandlerHeight;

typedef NS_ENUM(NSUInteger, DWExploreWhereToSpendSections) {
    DWExploreWhereToSpendSectionsSegments,
    DWExploreWhereToSpendSectionsSearch,
    DWExploreWhereToSpendSectionsFilters,
    DWExploreWhereToSpendSectionsItems,
};

typedef NS_ENUM(NSUInteger, DWExploreWhereToSpendSegment) {
    DWExploreWhereToSpendSegmentOnline,
    DWExploreWhereToSpendSegmentNearby,
    DWExploreWhereToSpendSegmentAll,
};

@interface DWExploreWhereToSpendViewController () <UITableViewDataSource, UITableViewDelegate, DWLocationObserver>

@property (nonatomic, strong) NSLayoutConstraint *contentViewTopLayoutConstraint;
@property (readonly, nonatomic, strong) UIView *contentView;
@property (readonly, nonatomic, strong) UITableView *tableView;
@property (readonly, nonatomic, strong) DWExploreWhereToSpendMapView *mapView;
@property (readonly, nonatomic, strong) NSArray<NSString *> *segmentTitles;
@property (nonatomic, strong) NSArray<DWExploreMerchant *> *merchants;
@property (readonly, nonatomic, assign) DWExploreWhereToSpendSegment currentSegment;
@property (nonatomic, strong) UIButton *showMapButton;
@end

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

- (void)updateMapVisibility {
    if(_currentSegment != DWExploreWhereToSpendSegmentNearby || DWLocationManager.shared.isPermissionDenied) {
        [self hideMapIfNeeded];
    }else{
        [self showMapIfNeeded];
    }
}

- (void)showMapIfNeeded {
    if(_currentSegment != DWExploreWhereToSpendSegmentNearby) { return; }
    
    if(DWLocationManager.shared.needsAuthorization) {
        [DWExploreWhereToSpendLocationServicePopup showInView:self.view completion:^{
            [DWLocationManager.shared requestAuthorization];
        }];
    }else if(DWLocationManager.shared.isAuthorized) {
        [self showMap];
    }
}

- (void)showMap {
    [UIView animateWithDuration:0.3 animations:^{
        self.contentViewTopLayoutConstraint.constant = kDefaultOpenedMapPosition;
        [self.view layoutIfNeeded];
    } completion:^(BOOL finished) {
        [self updateShowMapButtonVisibility];
    }];
}

- (void)hideMapIfNeeded {
    [UIView animateWithDuration:0.3 animations:^{
        self.contentViewTopLayoutConstraint.constant = kDefaultClosedMapPosition;
        [self.view layoutIfNeeded];
    } completion:^(BOOL finished) {
        [self updateShowMapButtonVisibility];
    }];
}

- (void)updateShowMapButtonVisibility {
    BOOL isVisible = _currentSegment == DWExploreWhereToSpendSegmentNearby &&
                     _contentViewTopLayoutConstraint.constant == kDefaultClosedMapPosition;
    isVisible = isVisible && DWLocationManager.shared.isAuthorized;
    
    _showMapButton.hidden = !isVisible;
}

- (UIBarButtonItem *)cancelBarButton {
    UIButton* infoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
    [infoButton addTarget:self action:@selector(infoAction) forControlEvents:UIControlEventTouchUpInside];
    UIBarButtonItem* infoBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:infoButton];
    return infoBarButtonItem;
}

- (void)segmentedControlDidChangeWithIndex:(NSInteger)index {
    if(_currentSegment == index) { return ;}

    _currentSegment = index;

    if(index == DWExploreWhereToSpendSegmentNearby) {
        [self showMapIfNeeded];
    }else{
        [self hideMapIfNeeded];
    }
    
    [_tableView reloadData];
}

-(void)move:(UIPanGestureRecognizer*)sender {
    CGPoint translatedPoint = [sender translationInView:self.view];

    _contentViewTopLayoutConstraint.constant += translatedPoint.x;
    _contentViewTopLayoutConstraint.constant += translatedPoint.y;

    [sender setTranslation:CGPointZero inView:self.view];

    if(sender.state == UIGestureRecognizerStateEnded) {
        CGFloat velocityY = (0.2*[sender velocityInView:self.view].y);
        CGFloat finalY = _contentViewTopLayoutConstraint.constant + velocityY;

        if(finalY < kDefaultOpenedMapPosition/2) {
            finalY = kDefaultClosedMapPosition;
        }else if (finalY > self.view.frame.size.height/2) {
            finalY = self.mapView.frame.size.height - kHandlerHeight;
        }else{
            finalY = kDefaultOpenedMapPosition;
        }

        CGFloat animationDuration = (ABS(velocityY)*.0002)+.2;

        [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.contentViewTopLayoutConstraint.constant = finalY;
            [self.view layoutIfNeeded];
        } completion:^(BOOL finished) {
            [self updateShowMapButtonVisibility];
        }];
    }

}
- (void)configureHierarchy {
    DWExploreWhereToSpendMapView *mapView = [[DWExploreWhereToSpendMapView alloc] initWithFrame:CGRectZero];
    mapView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:mapView];
    _mapView = mapView;

    UIView *contentView = [[UIView alloc] init];
    contentView.backgroundColor = [UIColor dw_backgroundColor];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    contentView.clipsToBounds = NO;
    [contentView.layer setMasksToBounds:YES];
    [contentView.layer setCornerRadius:20.0];
    [contentView.layer setMaskedCorners:kCALayerMinXMinYCorner|kCALayerMaxXMinYCorner];
    [self.view addSubview:contentView];
    _contentView = contentView;

    DWExploreWhereToSpendHandlerView *handlerView = [[DWExploreWhereToSpendHandlerView alloc] initWithFrame:CGRectZero];
    handlerView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:handlerView];

    UIPanGestureRecognizer *panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(move:)];
    [panRecognizer setMinimumNumberOfTouches:1];
    [panRecognizer setMaximumNumberOfTouches:1];
    [handlerView addGestureRecognizer:panRecognizer];

    UITableView *tableView = [UITableView new];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.delegate = self;
    tableView.showsVerticalScrollIndicator = NO;
    tableView.dataSource = self;
    tableView.clipsToBounds = NO;
    [tableView registerClass:[DWExploreWhereToSpendSegmentedCell class] forCellReuseIdentifier:DWExploreWhereToSpendSegmentedCell.dw_reuseIdentifier];
    [tableView registerClass:[DWExploreWhereToSpendSearchCell class] forCellReuseIdentifier:DWExploreWhereToSpendSearchCell.dw_reuseIdentifier];
    [tableView registerClass:[DWExploreWhereToSpendFiltersCell class] forCellReuseIdentifier:DWExploreWhereToSpendFiltersCell.dw_reuseIdentifier];
    [tableView registerClass:[DWExploreWhereToSpendItemCell class] forCellReuseIdentifier:DWExploreWhereToSpendItemCell.dw_reuseIdentifier];
    [tableView registerClass:[ExploreWhereToSpendLocationOffCell class] forCellReuseIdentifier:ExploreWhereToSpendLocationOffCell.dw_reuseIdentifier];
    
    [contentView addSubview:tableView];
    _tableView = tableView;

    self.showMapButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _showMapButton.translatesAutoresizingMaskIntoConstraints = NO;
    _showMapButton.hidden = YES;
    _showMapButton.tintColor = [UIColor whiteColor];
    _showMapButton.imageEdgeInsets = UIEdgeInsetsMake(0, -10, 0, 0);
    [_showMapButton addTarget:self action:@selector(showMap) forControlEvents:UIControlEventTouchUpInside];
    [_showMapButton setImage:[UIImage systemImageNamed:@"map.fill"] forState:UIControlStateNormal];
    [_showMapButton setTitle:NSLocalizedString(@"Map", nil) forState:UIControlStateNormal];
    [_showMapButton.layer setMasksToBounds:YES];
    [_showMapButton.layer setCornerRadius:20.0];
    [_showMapButton.layer setBackgroundColor:[UIColor blackColor].CGColor];
    [contentView addSubview:_showMapButton];
    
    CGFloat handlerViewHeight = 24;

    _contentViewTopLayoutConstraint = [contentView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:-handlerViewHeight];

    [NSLayoutConstraint activateConstraints:@[
            _contentViewTopLayoutConstraint,
            [contentView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
            [contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [contentView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

            [handlerView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
            [handlerView.heightAnchor constraintEqualToConstant:handlerViewHeight],
            [handlerView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
            [handlerView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],

            [tableView.topAnchor constraintEqualToAnchor:handlerView.bottomAnchor],
            [tableView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
            [tableView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
            [tableView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],

            [mapView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
            [mapView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
            [mapView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [mapView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            
            [_showMapButton.widthAnchor constraintEqualToConstant:92.0f],
            [_showMapButton.heightAnchor constraintEqualToConstant:40.0f],
            [_showMapButton.centerXAnchor constraintEqualToAnchor:_contentView.centerXAnchor],
            [_showMapButton.bottomAnchor constraintEqualToAnchor:_contentView.bottomAnchor constant:-15],
            
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear: animated];
    
    [DWLocationManager.shared addWithObserver:self];
    
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self showInfoViewControllerIfNeeded];
    [self showMapIfNeeded];
}

- (void)viewWillDisappear:(BOOL)animated {
    [DWLocationManager.shared removeWithObserver:self];
    
    [super viewWillDisappear:animated];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.merchants = [DWExploreMerchant mockData];

    self.title = NSLocalizedString(@"Where to Spend", nil);
    self.view.backgroundColor = [UIColor dw_backgroundColor];
    self.navigationItem.rightBarButtonItem = [self cancelBarButton];

    _segmentTitles = @[NSLocalizedString(@"Online", nil), NSLocalizedString(@"Nearby", nil), NSLocalizedString(@"All", nil)];
    _currentSegment = DWLocationManager.shared.isAuthorized ? DWExploreWhereToSpendSegmentNearby : DWExploreWhereToSpendSegmentOnline;

    [self configureHierarchy];
}

- (nonnull UITableViewCell *)tableView:(nonnull UITableView *)tableView cellForRowAtIndexPath:(nonnull NSIndexPath *)indexPath {
    UITableViewCell *cell;
    switch(indexPath.section) {
        case DWExploreWhereToSpendSectionsSegments:
        {
            DWExploreWhereToSpendSegmentedCell *segmentsCell = [tableView dequeueReusableCellWithIdentifier:DWExploreWhereToSpendSegmentedCell.dw_reuseIdentifier forIndexPath:indexPath];
            segmentsCell.separatorInset = UIEdgeInsetsMake(0, 2000, 0, 0);
            __block typeof(self) weakSelf = self;
            segmentsCell.segmentDidChangeBlock = ^(NSInteger index) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }
                [strongSelf segmentedControlDidChangeWithIndex:index ];
            };
            [segmentsCell updateWithItems:_segmentTitles andSelectedIndex:_currentSegment];
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
            filterCell.title = _segmentTitles[_currentSegment];
            filterCell.subtitle = nil;
            
            if(_currentSegment == DWExploreWhereToSpendSegmentNearby) {
                NSString *location = [DWLocationManager.shared currentReversedLocation];
                filterCell.title = location ? location : filterCell.title;
                filterCell.subtitle = NSLocalizedString(@"2 merchants in 20 miles", nil);
            }
            
            cell = filterCell;
            break;
        }
        case DWExploreWhereToSpendSectionsItems:
        {
            if(_currentSegment == DWExploreWhereToSpendSegmentNearby && DWLocationManager.shared.isPermissionDenied)
            {
                ExploreWhereToSpendLocationOffCell *itemCell = [tableView dequeueReusableCellWithIdentifier:ExploreWhereToSpendLocationOffCell.dw_reuseIdentifier forIndexPath:indexPath];
                cell = itemCell;
                cell.separatorInset = UIEdgeInsetsMake(0, 2000, 0, 0);
            }else{
                DWExploreMerchant *merchant = self.merchants[indexPath.row];
                DWExploreWhereToSpendItemCell *itemCell = [tableView dequeueReusableCellWithIdentifier:DWExploreWhereToSpendItemCell.dw_reuseIdentifier forIndexPath:indexPath];
                [itemCell updateWithMerchant:merchant];
                cell = itemCell;
                break;
            }
        }
    }

    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;

}

- (NSInteger)tableView:(nonnull UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if(section == DWExploreWhereToSpendSectionsFilters || section == DWExploreWhereToSpendSectionsSearch) {
        if(_currentSegment == DWExploreWhereToSpendSegmentNearby) {
            return DWLocationManager.shared.isPermissionDenied ? 0 : 1;
        }
    }
    
    if(section == DWExploreWhereToSpendSectionsItems) {
        if(_currentSegment == DWExploreWhereToSpendSegmentNearby) {
            if(DWLocationManager.shared.isAuthorized){
                return self.merchants.count;
            }else if(DWLocationManager.shared.needsAuthorization) {
                return 0;
            }else if(DWLocationManager.shared.isPermissionDenied) {
                return 1;
            }
        }else{
            return self.merchants.count;
        }
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
            return 50.0f;
            break;
        case DWExploreWhereToSpendSectionsFilters:
            return 50.0f;
            break;
        case DWExploreWhereToSpendSectionsItems:
            return (_currentSegment == DWExploreWhereToSpendSegmentNearby && DWLocationManager.shared.isPermissionDenied) ? tableView.frame.size.height : 56.0f;
            break;
    }

    return 0.0f;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    
    if(indexPath.section == DWExploreWhereToSpendSectionsItems) {
        DWExploreMerchant *merchant = self.merchants[indexPath.row];
        
        UIViewController *vc;
        if(merchant.isOnlineMerchant) {
            ExploreOnlineMerchantViewController *onlineVC = [[ExploreOnlineMerchantViewController alloc] initWithMerchant:merchant];
            onlineVC.payWithDashHandler = self.payWithDashHandler;
            vc = onlineVC;
        }else{
            vc = [[ExploreOfflineMerchantViewController alloc] initWithMerchant:merchant isShowAllHidden:NO];
        }
        
        [self.navigationController pushViewController:vc animated:YES];
    }
}
- (void)locationManagerDidChangeCurrentLocation:(DWLocationManager * _Nonnull)manager {
    
}

- (void)locationManagerDidChangeCurrentReversedLocation:(DWLocationManager * _Nonnull)manager {
    if(_currentSegment == DWExploreWhereToSpendSegmentNearby) {
        [_tableView reloadData];
    }
}

- (void)locationManagerDidChangeServiceAvailability:(DWLocationManager * _Nonnull)manager {
    if(_currentSegment == DWExploreWhereToSpendSegmentNearby) {
        [_tableView reloadData];
        [self updateMapVisibility];
    }
}

@end





