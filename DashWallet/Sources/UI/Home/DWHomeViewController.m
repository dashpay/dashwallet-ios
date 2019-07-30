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

#import "DWHomeViewController.h"

#import "DWHomeModel.h"
#import "DWHomeView.h"
#import "DWNavigationController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWHomeViewController ()

@property (strong, nonatomic) DWHomeView *view;

@end

@implementation DWHomeViewController

@dynamic view;

+ (UIViewController *)controllerEmbededInNavigation {
    DWHomeViewController *controller = [[DWHomeViewController alloc] init];
    DWNavigationController *navigationController =
        [[DWNavigationController alloc] initWithRootViewController:controller];

    return navigationController;
}

- (void)loadView {
    CGRect frame = [UIScreen mainScreen].bounds;
    self.view = [[DWHomeView alloc] initWithFrame:frame];
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - Private

- (void)setupView {
    UIImage *logoImage = [UIImage imageNamed:@"dash_logo"];
    NSParameterAssert(logoImage);
    self.navigationItem.titleView = [[UIImageView alloc] initWithImage:logoImage];

    self.view.model = [[DWHomeModel alloc] init];
}

@end

NS_ASSUME_NONNULL_END
