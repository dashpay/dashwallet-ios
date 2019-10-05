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

#import "DWMainMenuViewController.h"

#import "DWMainMenuContentView.h"
#import "DWMainMenuModel.h"
#import "DWSecurityMenuViewController.h"
#import "DWSettingsMenuViewController.h"
#import "DWToolsMenuViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWMainMenuViewController () <DWMainMenuContentViewDelegate>

@property (nonatomic, strong) DWMainMenuContentView *view;

@end

@implementation DWMainMenuViewController

@dynamic view;

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        self.title = NSLocalizedString(@"More", nil);
    }
    return self;
}

- (void)loadView {
    CGRect frame = [UIScreen mainScreen].bounds;
    self.view = [[DWMainMenuContentView alloc] initWithFrame:frame];
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view.delegate = self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.model = [[DWMainMenuModel alloc] init];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - DWMainMenuContentViewDelegate

- (void)mainMenuContentView:(DWMainMenuContentView *)view didSelectMenuItem:(id<DWMainMenuItem>)item {
    switch (item.type) {
        case DWMainMenuItemType_BuySellDash: {

            break;
        }
        case DWMainMenuItemType_Security: {
            DWSecurityMenuViewController *controller = [[DWSecurityMenuViewController alloc] init];
            [self.navigationController pushViewController:controller animated:YES];

            break;
        }
        case DWMainMenuItemType_Settings: {
            DWSettingsMenuViewController *controller = [[DWSettingsMenuViewController alloc] init];
            [self.navigationController pushViewController:controller animated:YES];

            break;
        }
        case DWMainMenuItemType_Tools: {
            DWToolsMenuViewController *controller = [[DWToolsMenuViewController alloc] init];
            [self.navigationController pushViewController:controller animated:YES];

            break;
        }
    }
}

@end

NS_ASSUME_NONNULL_END
