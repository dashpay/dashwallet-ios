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

#import "DWDemoAppRootViewController.h"

#import "DWDemoMainTabbarViewController.h"
#import "DWRootModelStub.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWDemoAppRootViewController

- (instancetype)init {
    self = [super initWithModel:[[DWRootModelStub alloc] init]];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

#if SNAPSHOT
    // nop
#else
    self.view.userInteractionEnabled = NO;
#endif /* SNAPSHOT */
}

+ (Class)mainControllerClass {
    return [DWDemoMainTabbarViewController class];
}

#pragma mark - Demo Mode

- (BOOL)demoMode {
#if SNAPSHOT
    return NO;
#else
    return YES;
#endif /* SNAPSHOT */
}

#pragma mark - DWNavigationFullscreenable

- (BOOL)requiresNoNavigationBar {
    return YES;
}

@end

NS_ASSUME_NONNULL_END
