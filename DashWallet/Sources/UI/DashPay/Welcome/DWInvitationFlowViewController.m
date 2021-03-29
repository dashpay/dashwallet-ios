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

#import "DWInvitationFlowViewController.h"

#import "DWDPWelcomeViewController.h"
#import "DWGetStartedViewController.h"
#import "DWNavigationController.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWInvitationFlowViewController () <DWDPWelcomeViewControllerDelegate,
                                              DWGetStartedViewControllerDelegate>

@property (nonatomic, strong) DWNavigationController *navController;

@end

NS_ASSUME_NONNULL_END

@implementation DWInvitationFlowViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_backgroundColor];

    DWDPWelcomeViewController *welcomeController = [[DWDPWelcomeViewController alloc] init];
    welcomeController.delegate = self;
    DWNavigationController *navController = [[DWNavigationController alloc] initWithRootViewController:welcomeController];
    [self dw_embedChild:navController];
    self.navController = navController;
}

#pragma mark - DWNavigationFullscreenable

- (BOOL)requiresNoNavigationBar {
    return YES;
}

#pragma mark - DWDPWelcomeViewControllerDelegate

- (void)welcomeViewControllerDidFinish:(DWDPWelcomeViewController *)controller {
    DWGetStartedViewController *getStarted = [[DWGetStartedViewController alloc] initWithPage:DWGetStartedPage_1];
    getStarted.delegate = self;
    [self.navController setViewControllers:@[ getStarted ] animated:YES];
}

#pragma mark - DWGetStartedViewControllerDelegate

- (void)getStartedViewControllerDidContinue:(DWGetStartedViewController *)controller {
    if (controller.page == DWGetStartedPage_1) {
        DWGetStartedViewController *getStarted = [[DWGetStartedViewController alloc] initWithPage:DWGetStartedPage_2];
        getStarted.delegate = self;
        [self.navController setViewControllers:@[ getStarted ] animated:YES];
    }
    else if (controller.page == DWGetStartedPage_2) {
        DWGetStartedViewController *getStarted = [[DWGetStartedViewController alloc] initWithPage:DWGetStartedPage_3];
        getStarted.delegate = self;
        [self.navController setViewControllers:@[ getStarted ] animated:YES];
    }
    else {
        // DONE
    }
}

@end
