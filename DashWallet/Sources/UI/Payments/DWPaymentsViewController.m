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

#import "DWPaymentsViewController.h"

#import "DWControllerCollectionView.h"
#import "DWPayViewController.h"
#import "DWReceiveViewController.h"
#import "DWSegmentedControl.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const CURRENT_SELECTED_INDEX_KEY = @"DW_PAYMENTS_CURRENT_PAGE";

@interface DWPaymentsViewController () <DWControllerCollectionViewDataSource,
                                        UICollectionViewDelegateFlowLayout>

@property (strong, nonatomic) IBOutlet UILabel *navigationTitleLabel;
@property (strong, nonatomic) IBOutlet DWSegmentedControl *segmentedControl;
@property (strong, nonatomic) IBOutlet DWControllerCollectionView *controllerCollectionView;

@property (nonatomic, strong) DWReceiveModel *receiveModel;
@property (nonatomic, strong) DWPayModel *payModel;
@property (nonatomic, strong) id<DWTransactionListDataProviderProtocol> dataProvider;

@property (nonatomic, strong) DWPayViewController *payViewController;
@property (nonatomic, strong) DWReceiveViewController *receiveViewController;

@property (nonatomic, assign) BOOL didPerformInitialPageOpen;
@property (nullable, nonatomic, strong) NSIndexPath *prevIndexPathAtCenter;

@end

@implementation DWPaymentsViewController

+ (instancetype)controllerWithReceiveModel:(DWReceiveModel *)receiveModel
                                  payModel:(DWPayModel *)payModel
                              dataProvider:(id<DWTransactionListDataProviderProtocol>)dataProvider {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Payments" bundle:nil];
    DWPaymentsViewController *controller = [storyboard instantiateInitialViewController];
    controller.receiveModel = receiveModel;
    controller.payModel = payModel;
    controller.dataProvider = dataProvider;

    return controller;
}

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        _currentIndex = DWPaymentsViewControllerIndex_None;
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        _currentIndex = DWPaymentsViewControllerIndex_None;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
    [self setupControllers];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDefault;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    self.prevIndexPathAtCenter = [self currentIndexPath];

    [coordinator
        animateAlongsideTransition:nil
                        completion:^(id<UIViewControllerTransitionCoordinatorContext> _Nonnull context) {
                            [self.controllerCollectionView.collectionViewLayout invalidateLayout];
                            [self scrollToIndexPath:self.prevIndexPathAtCenter animated:NO];
                        }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self.controllerCollectionView reloadData];

    if (!self.didPerformInitialPageOpen) {
        self.didPerformInitialPageOpen = YES;

        // scroll to needed index when reloadData finishes

        [self.controllerCollectionView
            performBatchUpdates:^{
            }
            completion:^(BOOL finished) {
                DWPaymentsViewControllerIndex previousIndex = [self previouslySelectedPageIndex];
                if (self.currentIndex == DWPaymentsViewControllerIndex_None) {
                    self.currentIndex = previousIndex;
                }
                NSIndexPath *indexPath = [NSIndexPath indexPathForItem:self.currentIndex inSection:0];
                [self scrollToIndexPath:indexPath animated:NO];
            }];
    }
}


- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self saveCurrentSelectedPageIndex];
}

#pragma mark - DWNavigationFullscreenable

- (BOOL)requiresNoNavigationBar {
    return YES;
}

#pragma mark - Private

- (void)setupView {
    self.navigationTitleLabel.text = NSLocalizedString(@"Payments", nil);

    NSArray<NSString *> *items = @[
        NSLocalizedString(@"Pay", nil),
        NSLocalizedString(@"Receive", nil),
    ];
    self.segmentedControl.shouldAnimateSelection = NO;
    self.segmentedControl.items = items;
    [self.segmentedControl addTarget:self
                              action:@selector(segmentedControlAction:)
                    forControlEvents:UIControlEventValueChanged];

    self.controllerCollectionView.delegate = self;
    self.controllerCollectionView.controllerDataSource = self;
    self.controllerCollectionView.containerViewController = self;
}

- (void)setupControllers {
    self.payViewController = [DWPayViewController controllerWithModel:self.payModel
                                                         dataProvider:self.dataProvider];
    self.receiveViewController = [DWReceiveViewController controllerWithModel:self.receiveModel];
}

#pragma mark - Actions

- (IBAction)cancelButtonAction:(id)sender {
    [self.delegate paymentsViewControllerDidCancel:self];
}

- (void)segmentedControlAction:(DWSegmentedControl *)sender {
    NSIndexPath *indexPath = [NSIndexPath indexPathForItem:sender.selectedSegmentIndex inSection:0];
    [self scrollToIndexPath:indexPath animated:YES];
}

#pragma mark DWControllerCollectionViewDataSource

- (NSInteger)numberOfItemsInControllerCollectionView:(DWControllerCollectionView *)view {
    return 2;
}

- (UIViewController *)controllerCollectionView:(DWControllerCollectionView *)view controllerForIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.item == DWPaymentsViewControllerIndex_Pay) {
        return self.payViewController;
    }
    else {
        NSAssert(indexPath.item == DWPaymentsViewControllerIndex_Receive, @"Invalid datasource");
        return self.receiveViewController;
    }
}

#pragma mark UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return collectionView.bounds.size;
}

- (CGPoint)collectionView:(UICollectionView *)collectionView targetContentOffsetForProposedContentOffset:(CGPoint)proposedContentOffset {
    NSIndexPath *indexPath = self.prevIndexPathAtCenter;
    if (!indexPath) {
        return proposedContentOffset;
    }

    UICollectionViewLayoutAttributes *attributes =
        [collectionView layoutAttributesForItemAtIndexPath:indexPath];
    if (!attributes) {
        return proposedContentOffset;
    }

    const CGPoint newOriginForOldCenter = attributes.frame.origin;
    return newOriginForOldCenter;
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    const CGFloat offset = scrollView.contentOffset.x;
    const CGFloat pageWidth = CGRectGetWidth(scrollView.bounds);
    if (pageWidth == 0.0) {
        return;
    }

    const CGFloat percent = offset / pageWidth;
    self.segmentedControl.selectedSegmentIndexPercent = percent;
}

#pragma mark - Private

- (nullable NSIndexPath *)currentIndexPath {
    const CGPoint center = [self.view convertPoint:self.controllerCollectionView.center toView:self.controllerCollectionView];
    NSIndexPath *indexPath = [self.controllerCollectionView indexPathForItemAtPoint:center];

    return indexPath;
}

- (void)scrollToIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated {
    NSParameterAssert(indexPath);
    if (!indexPath) {
        return;
    }

    [self.controllerCollectionView scrollToItemAtIndexPath:indexPath
                                          atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally
                                                  animated:animated];
}

- (DWPaymentsViewControllerIndex)previouslySelectedPageIndex {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSNumber *currentPageNumber = [userDefaults objectForKey:CURRENT_SELECTED_INDEX_KEY];
    if (currentPageNumber) {
        return currentPageNumber.integerValue;
    }
    else {
        return DWPaymentsViewControllerIndex_Pay;
    }
}

- (void)saveCurrentSelectedPageIndex {
    const NSInteger currentIndex = self.segmentedControl.selectedSegmentIndex;
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setInteger:currentIndex forKey:CURRENT_SELECTED_INDEX_KEY];
}

@end

NS_ASSUME_NONNULL_END
