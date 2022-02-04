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

#import "DWExploreBaseInfoViewController.h"
#import "DWUIKit.h"

@interface DWExploreBaseInfoViewController ()

@end

@implementation DWExploreBaseInfoViewController

-(void)closeButtonAction {
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(void)configureHierarchy {
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [closeButton setImage:[UIImage imageNamed:@"close.button"] forState:UIControlStateNormal];
    [closeButton addTarget:self
                    action:@selector(closeButtonAction)
          forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:closeButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [closeButton.widthAnchor constraintEqualToConstant:30],
        [closeButton.heightAnchor constraintEqualToConstant:30],
        [closeButton.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:12],
        [closeButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15],
    ]];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor dw_backgroundColor];
    
    [self configureHierarchy];
}

@end
