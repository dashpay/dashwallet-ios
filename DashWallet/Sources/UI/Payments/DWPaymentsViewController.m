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

#import "DWSegmentedControl.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWPaymentsViewController ()

@property (strong, nonatomic) IBOutlet DWSegmentedControl *segmentedControl;

@end

@implementation DWPaymentsViewController

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Payments" bundle:nil];
    DWPaymentsViewController *controller = [storyboard instantiateInitialViewController];

    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupView];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDefault;
}

#pragma mark - DWNavigationFullscreenable

- (BOOL)requiresNoNavigationBar {
    return YES;
}

#pragma mark - Private

- (void)setupView {
    NSArray<NSString *> *items = @[
        NSLocalizedString(@"Pay", nil),
        NSLocalizedString(@"Receive", nil),
    ];
    self.segmentedControl.items = items;
}

@end

NS_ASSUME_NONNULL_END
