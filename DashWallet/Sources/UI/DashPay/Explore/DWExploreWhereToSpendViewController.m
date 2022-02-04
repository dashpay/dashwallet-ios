//  
//  Created by Pavel Tikhonenko
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

#import "DWExploreWhereToSpendViewController.h"
#import "DWExploreWhereToSpendInfoViewController.h"
#import "DWUIKit.h"

@interface DWExploreWhereToSpendViewController ()

@end

@implementation DWExploreWhereToSpendViewController

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    DWExploreWhereToSpendInfoViewController *vc = [[DWExploreWhereToSpendInfoViewController alloc] init];
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor dw_backgroundColor];
}

@end
