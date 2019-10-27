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

#import "DWModalNavigationController.h"

#import "DWModalPopupTransition.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWModalNavigationController ()

@property (nonatomic, strong) DWModalPopupTransition *modalTransition;

@end

@implementation DWModalNavigationController

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        [self modalNavigationController_setup];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self modalNavigationController_setup];
    }
    return self;
}

#pragma mark - Private

- (void)modalNavigationController_setup {
    DWModalPopupTransition *modalTransition = [[DWModalPopupTransition alloc] init];
    modalTransition.appearanceStyle = DWModalPopupAppearanceStyle_Fullscreen;

    self.modalTransition = modalTransition;
    self.transitioningDelegate = modalTransition;
    self.modalPresentationStyle = UIModalPresentationCustom;
    self.modalPresentationCapturesStatusBarAppearance = YES;
}

@end

NS_ASSUME_NONNULL_END
