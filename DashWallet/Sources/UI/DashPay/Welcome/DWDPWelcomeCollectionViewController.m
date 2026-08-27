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

#import "DWDPWelcomeCollectionViewController.h"

#import "DWControllerCollectionView.h"
#import "DWDPWelcomePageViewController.h"
#import "DWPassthroughStackView.h"
#import "DWPassthroughView.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

static CGFloat const SPACE_BEFORE_PAGE = 225;

@interface DWDPWelcomeCollectionViewController () <DWControllerCollectionViewDataSource,
                                                   UICollectionViewDelegateFlowLayout>

@property (null_resettable, nonatomic, strong) DWControllerCollectionView *controllerCollectionView;
@property (null_resettable, nonatomic, strong) NSArray<UIViewController *> *controllers;
@property (nullable, nonatomic, strong) NSIndexPath *prevIndexPathAtCenter;
@property (null_resettable, nonatomic, strong) UIPageControl *pageControl;

@end

NS_ASSUME_NONNULL_END

@implementation DWDPWelcomeCollectionViewController

- (BOOL)canSwitchToNext {
    return [self currentIndexPath].item < self.controllers.count - 1;
}

- (void)switchToNext {
    NSAssert([self canSwitchToNext], @"Inconsistent state");

    NSIndexPath *indexPath = [NSIndexPath indexPathForItem:[self currentIndexPath].item + 1 inSection:0];
    [self scrollToIndexPath:indexPath animated:YES];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_backgroundColor];

    [self.view addSubview:self.controllerCollectionView];

    DWPassthroughView *imageLikeView = [[DWPassthroughView alloc] init];
    imageLikeView.translatesAutoresizingMaskIntoConstraints = NO;

    DWPassthroughStackView *stack = [[DWPassthroughStackView alloc] initWithArrangedSubviews:@[ imageLikeView, self.pageControl ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.spacing = 35;
    stack.axis = UILayoutConstraintAxisVertical;
    [self.view addSubview:stack];

    UIView *parent = self.view;
    CGFloat padding = 20;
    [NSLayoutConstraint activateConstraints:@[
        [self.controllerCollectionView.topAnchor constraintEqualToAnchor:parent.topAnchor],
        [self.controllerCollectionView.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor],
        [parent.trailingAnchor constraintEqualToAnchor:self.controllerCollectionView.trailingAnchor],
        [parent.bottomAnchor constraintEqualToAnchor:self.controllerCollectionView.bottomAnchor],

        [stack.topAnchor constraintGreaterThanOrEqualToAnchor:parent.topAnchor],
        [parent.bottomAnchor constraintGreaterThanOrEqualToAnchor:stack.bottomAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:parent.centerYAnchor],

        [stack.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor
                                            constant:padding],
        [parent.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor
                                              constant:padding],

        [imageLikeView.heightAnchor constraintEqualToConstant:SPACE_BEFORE_PAGE],
    ]];
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
    const NSInteger pageCount = self.pageControl.numberOfPages;
    const NSInteger page = floor((offset - pageWidth / pageCount) / pageWidth) + 1;
    self.pageControl.currentPage = page;
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

#pragma mark - DWControllerCollectionViewDataSource

- (NSInteger)numberOfItemsInControllerCollectionView:(DWControllerCollectionView *)view {
    return self.controllers.count;
}

- (UIViewController *)controllerCollectionView:(DWControllerCollectionView *)view
                        controllerForIndexPath:(NSIndexPath *)indexPath {
    return self.controllers[indexPath.item];
}

- (DWControllerCollectionView *)controllerCollectionView {
    if (_controllerCollectionView == nil) {
        UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
        layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        layout.sectionInset = UIEdgeInsetsZero;
        layout.minimumLineSpacing = 0;
        layout.minimumInteritemSpacing = 0;

        DWControllerCollectionView *collectionView =
            [[DWControllerCollectionView alloc] initWithFrame:self.view.bounds
                                         collectionViewLayout:layout];
        collectionView.translatesAutoresizingMaskIntoConstraints = NO;
        collectionView.controllerDataSource = self;
        collectionView.backgroundColor = [UIColor dw_backgroundColor];
        collectionView.delegate = self;
        collectionView.pagingEnabled = YES;
        collectionView.containerViewController = self;
        collectionView.showsHorizontalScrollIndicator = NO;
        _controllerCollectionView = collectionView;
    }
    return _controllerCollectionView;
}

- (UIPageControl *)pageControl {
    if (_pageControl == nil) {
        _pageControl = [[UIPageControl alloc] init];
        _pageControl.translatesAutoresizingMaskIntoConstraints = NO;
        _pageControl.numberOfPages = self.controllers.count;
        _pageControl.currentPage = 0;
        _pageControl.currentPageIndicatorTintColor = [UIColor dw_dashBlueColor];
        _pageControl.pageIndicatorTintColor = [UIColor dw_lightBlueColor];
        _pageControl.userInteractionEnabled = NO;
    }
    return _pageControl;
}

- (NSArray<UIViewController *> *)controllers {
    if (_controllers == nil) {
        _controllers = @[
            [[DWDPWelcomePageViewController alloc] initWithIndex:0],
            [[DWDPWelcomePageViewController alloc] initWithIndex:1],
            [[DWDPWelcomePageViewController alloc] initWithIndex:2],
        ];
    }
    return _controllers;
}

@end
