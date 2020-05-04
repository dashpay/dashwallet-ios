//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWUserProfileViewController.h"

#import "DWEnvironment.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUserProfileViewController ()

@property (nonatomic, strong) DSBlockchainIdentity *blockchainIdentity;

@end

NS_ASSUME_NONNULL_END

@implementation DWUserProfileViewController

- (instancetype)initWithBlockchainIdentity:(DSBlockchainIdentity *)blockchainIdentity {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _blockchainIdentity = blockchainIdentity;

        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (DWNavigationBarAppearance)navigationBarAppearance {
    return DWNavigationBarAppearanceWhite;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Profile";

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];
}

@end
