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
#import "DevicesCompatibility.h"
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
@property (nonatomic, strong) UIImageView *bezelImageView;

@property (null_resettable, nonatomic, strong) DWOnboardingModel *model;

@property (nonatomic, strong) DWDemoAppRootViewController *rootController;
@property (nullable, nonatomic, strong) NSIndexPath *prevIndexPathAtCenter;

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

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    self.prevIndexPathAtCenter = [self currentIndexPath];

    [coordinator
        animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            const UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;
            const CGAffineTransform bezelsTransform = [self transformForDeviceOrientation:deviceOrientation];
            self.bezelImageView.transform = bezelsTransform;

            [self.collectionView.collectionViewLayout invalidateLayout];
        }
        completion:^(id<UIViewControllerTransitionCoordinatorContext> _Nonnull context) {
            [self scrollToIndexPath:self.prevIndexPathAtCenter animated:NO];
        }];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    const CGFloat height = CGRectGetHeight(self.view.bounds);
    const CGFloat width = CGRectGetWidth(self.view.bounds);

    const CGFloat scale = 0.5;
    const CGFloat miniWalletHeight = height * scale;
    const CGFloat offset = (height - miniWalletHeight) / 2.0;
    const CGAffineTransform scaleTransform = CGAffineTransformMakeScale(scale, scale);
    const CGAffineTransform resultTransform = CGAffineTransformTranslate(scaleTransform, 0.0, -offset);
    self.miniWalletView.transform = resultTransform;

    const CGSize bezelSize = self.bezelImageView.image.size;
    const CGSize scaledBezelSize = CGSizeMake(bezelSize.width * scale, bezelSize.height * scale);
    const CGFloat bezelY = ((height - scaledBezelSize.height) / 2.0) - offset / 2.0;

    self.bezelImageView.transform = CGAffineTransformIdentity;
    self.bezelImageView.frame = CGRectMake((width - scaledBezelSize.width) / 2.0,
                                           bezelY,
                                           scaledBezelSize.width,
                                           scaledBezelSize.height);

    const UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;
    const CGAffineTransform bezelsTransform = [self transformForDeviceOrientation:deviceOrientation];
    self.bezelImageView.transform = bezelsTransform;

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
    UIImage *bezelImage = [self bezelImageForCurrentDevice];
    UIImageView *bezelImageView = [[UIImageView alloc] initWithImage:bezelImage];
    bezelImageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.view insertSubview:bezelImageView aboveSubview:self.miniWalletView];
    self.bezelImageView = bezelImageView;

    self.pageControl.numberOfPages = self.model.items.count;
    self.pageControl.pageIndicatorTintColor = [UIColor dw_disabledButtonColor];
    self.pageControl.currentPageIndicatorTintColor = [UIColor dw_dashBlueColor];

    [self.skipButton setTitle:NSLocalizedString(@"skip", nil) forState:UIControlStateNormal];
    [self.finishButton setTitle:NSLocalizedString(@"Get Started", nil) forState:UIControlStateNormal];
    self.finishButton.alpha = 0.0;

    DWDemoAppRootViewController *controller = [[DWDemoAppRootViewController alloc] init];
    DWNavigationController *navigationController =
        [[DWNavigationController alloc] initWithRootViewController:controller];
    [self dw_embedChild:navigationController inContainer:self.miniWalletView];
    self.rootController = controller;
}

- (nullable NSIndexPath *)currentIndexPath {
    const CGPoint center = [self.view convertPoint:self.collectionView.center toView:self.collectionView];
    NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:center];

    return indexPath;
}

- (void)scrollToIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated {
    NSParameterAssert(indexPath);
    if (!indexPath) {
        return;
    }

    [self.collectionView scrollToItemAtIndexPath:indexPath
                                atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally
                                        animated:animated];
}

- (UIImage *)bezelImageForCurrentDevice {
    if (IS_IPHONE) {
        if (IS_IPHONE_X_FAMILY) {
            return [UIImage imageNamed:@"iphone_x_bezel"];
        }
        else if (IS_IPHONE_5_OR_LESS) {
            return [UIImage imageNamed:@"iphone_5_bezel"];
        }
        else {
            return [UIImage imageNamed:@"iphone_8_bezel"];
        }
    }
    else {
        if (IS_IPAD_PRO_11) {
            return [UIImage imageNamed:@"ipad_pro_11_bezel"];
        }
        else if (IS_IPAD_PRO_12_9) {
            return [UIImage imageNamed:@"ipad_pro_12_bezel"];
        }
        else {
            return [UIImage imageNamed:@"ipad_regular_bezel"];
        }
    }
}

- (CGAffineTransform)transformForDeviceOrientation:(UIDeviceOrientation)orientation {
    if (orientation == UIDeviceOrientationPortraitUpsideDown) {
        return CGAffineTransformMakeRotation(M_PI * 180 / 180.0);
    }
    else if (orientation == UIDeviceOrientationLandscapeLeft) {
        return CGAffineTransformMakeRotation(M_PI * 270 / 180.0);
    }
    else if (orientation == UIDeviceOrientationLandscapeRight) {
        return CGAffineTransformMakeRotation(M_PI * 90 / 180.0);
    }

    return CGAffineTransformIdentity;
}

@end

NS_ASSUME_NONNULL_END
