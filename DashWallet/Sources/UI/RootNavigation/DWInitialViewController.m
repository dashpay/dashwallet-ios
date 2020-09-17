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

#import "DWInitialViewController.h"

#import "DWAppRootViewController.h"
#import "DWGlobalOptions.h"
#import "DWOnboardingViewController.h"
#import "DWUIKit.h"

#if SNAPSHOT
#import "DWDemoAppRootViewController.h"
#endif /* SNAPSHOT */

NS_ASSUME_NONNULL_BEGIN

@interface DWInitialViewController () <DWOnboardingViewControllerDelegate>

@property (nonatomic, assign) BOOL launchingWasDeferred;
@property (nullable, nonatomic, strong) DWAppRootViewController *rootController;

@end

@implementation DWInitialViewController

#pragma mark - Life Cycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_backgroundColor];

#if SNAPSHOT
    DWDemoAppRootViewController *controller = [[DWDemoAppRootViewController alloc] init];
    [self transitionToController:controller];
#else
    if ([self shouldDisplayOnboarding]) {
        DWOnboardingViewController *onboarding = [DWOnboardingViewController controller];
        onboarding.delegate = self;
        [self transitionToController:onboarding];
    }
    else {
        DWAppRootViewController *rootController = [self createRootController];
        [self transitionToController:rootController];
        self.rootController = rootController;
    }
#endif /* SNAPSHOT */
}

#pragma mark - Public

- (void)setLaunchingAsDeferredController {
    self.launchingWasDeferred = YES;
    [self.rootController setLaunchingAsDeferredController];
}

- (void)handleURL:(NSURL *)url {
    [self.rootController handleURL:url];
}

- (void)handleFile:(NSData *)file {
    [self.rootController handleFile:file];
}

#pragma mark - DWOnboardingViewControllerDelegate

- (void)onboardingViewControllerDidFinish:(DWOnboardingViewController *)controller {
    [self onboardingDidFinish];

    DWAppRootViewController *rootController = [self createRootController];
    [rootController setLaunchingAsDeferredController]; // always deferred after onboarding
    [self transitionToController:rootController];
    self.rootController = rootController;
}

#pragma mark - Private

- (BOOL)shouldDisplayOnboarding {
    return [DWGlobalOptions sharedInstance].shouldDisplayOnboarding;
}

- (void)onboardingDidFinish {
    [DWGlobalOptions sharedInstance].shouldDisplayOnboarding = NO;
}

- (DWAppRootViewController *)createRootController {
    DWAppRootViewController *controller = [[DWAppRootViewController alloc] init];
    if (self.launchingWasDeferred) {
        [controller setLaunchingAsDeferredController];
    }

    return controller;
}

@end

NS_ASSUME_NONNULL_END
