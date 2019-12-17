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

#import "DWOnboardingViewController.h"

#import "DWDemoAdvancedSecurityViewController.h"
#import "DWDemoAppRootViewController.h"
#import "DWNavigationController.h"
#import "DWOnboardingCollectionViewCell.h"
#import "DWOnboardingModel.h"
#import "DWUIKit.h"
#import "UIViewController+DWEmbedding.h"

NS_ASSUME_NONNULL_BEGIN

static NSTimeInterval const ANIMATION_DURATION = 0.25;

@interface DWOnboardingViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout>

@property (strong, nonatomic) IBOutlet UIView *miniWalletView;
@property (strong, nonatomic) IBOutlet UICollectionView *collectionView;
@property (strong, nonatomic) IBOutlet UIPageControl *pageControl;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *contentBottomConstraint;
@property (strong, nonatomic) IBOutlet UIButton *skipButton;
@property (strong, nonatomic) IBOutlet UIButton *finishButton;

@property (null_resettable, nonatomic, strong) DWOnboardingModel *model;

@property (nonatomic, strong) DWDemoAppRootViewController *rootController;

@end

@implementation DWOnboardingViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Onboarding" bundle:nil];
    DWOnboardingViewController *controller = [storyboard instantiateInitialViewController];

    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    const CGFloat height = CGRectGetHeight(self.view.bounds);
    const CGFloat scale = 0.5;
    const CGFloat miniWalletHeight = height * scale;
    const CGFloat offset = (height - miniWalletHeight) / 2.0;
    const CGAffineTransform scaleTransform = CGAffineTransformMakeScale(scale, scale);
    self.miniWalletView.transform = CGAffineTransformTranslate(scaleTransform, 0.0, -offset);

    // There is an issue with layout margins of "minified" root controller
    // When the scale transformation is applied to the hosted view safe area is ignored and layout margins of
    // children views within root controller becomes invalid.
    // Restore safe area insets and hack horizontal insets a bit so it's fine for both root and their children.
    UIEdgeInsets insets = self.view.safeAreaInsets;
    insets.left = 10.0;
    insets.right = 10.0;
    UINavigationController *navigationController = self.rootController.navigationController;
    NSParameterAssert(navigationController);
    navigationController.additionalSafeAreaInsets = insets;
}

#pragma mark - Actions

- (IBAction)skipButtonAction:(id)sender {
    [self.delegate onboardingViewControllerDidFinish:self];
}

- (IBAction)pageValueChangedAction:(id)sender {
    NSIndexPath *indexPath = [NSIndexPath indexPathForItem:self.pageControl.currentPage inSection:0];
    [self.collectionView scrollToItemAtIndexPath:indexPath
                                atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally
                                        animated:YES];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.model.items.count;
}

#pragma mark - UICollectionViewDelegate

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = DWOnboardingCollectionViewCell.dw_reuseIdentifier;
    DWOnboardingCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:cellId
                                                                                     forIndexPath:indexPath];

    id<DWOnboardingPageProtocol> cellModel = self.model.items[indexPath.item];
    cell.model = cellModel;

    return cell;
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView
                    layout:(UICollectionViewLayout *)collectionViewLayout
    sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return collectionView.bounds.size;
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

    if (!scrollView.tracking) {
        static NSTimeInterval const delay = 0.15;
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                 selector:@selector(scrollViewDidStop)
                                                   object:nil];
        [self performSelector:@selector(scrollViewDidStop)
                   withObject:nil
                   afterDelay:delay
                      inModes:@[ NSDefaultRunLoopMode ]];
    }
}

- (void)scrollViewDidStop {
    UINavigationController *navigationController = self.rootController.navigationController;
    NSParameterAssert(navigationController);

    if (self.pageControl.currentPage == 0) {
        [navigationController popToRootViewControllerAnimated:YES];
        [self.rootController closePaymentsScreen];
    }
    else if (self.pageControl.currentPage == 1) {
        [navigationController popToRootViewControllerAnimated:YES];
        [self.rootController openPaymentsScreen];
    }
    else if (self.pageControl.currentPage == 2) {
        if (navigationController.viewControllers.count == 1) {
            DWDemoAdvancedSecurityViewController *controller = [[DWDemoAdvancedSecurityViewController alloc] init];
            [navigationController pushViewController:controller animated:YES];
        }
    }

    const BOOL canFinish = self.pageControl.currentPage == 2;
    [UIView animateWithDuration:ANIMATION_DURATION
                     animations:^{
                         self.skipButton.alpha = canFinish ? 0.0 : 1.0;
                         self.finishButton.alpha = canFinish ? 1.0 : 0.0;
                     }];
}

#pragma mark - Private

- (DWOnboardingModel *)model {
    if (!_model) {
        _model = [[DWOnboardingModel alloc] init];
    }

    return _model;
}

- (void)setupView {
    self.pageControl.numberOfPages = self.model.items.count;
    self.pageControl.pageIndicatorTintColor = [UIColor dw_disabledButtonColor];
    self.pageControl.currentPageIndicatorTintColor = [UIColor dw_dashBlueColor];

    [self.skipButton setTitle:NSLocalizedString(@"Skip", nil) forState:UIControlStateNormal];
    [self.finishButton setTitle:NSLocalizedString(@"Done", nil) forState:UIControlStateNormal];
    self.finishButton.alpha = 0.0;

    DWDemoAppRootViewController *controller = [[DWDemoAppRootViewController alloc] init];
    DWNavigationController *navigationController =
        [[DWNavigationController alloc] initWithRootViewController:controller];
    [self dw_embedChild:navigationController inContainer:self.miniWalletView];
    self.rootController = controller;
}

@end

NS_ASSUME_NONNULL_END
