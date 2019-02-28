//  
//  Created by Sam Westrich
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

#import "DWKeysOverviewViewController.h"

@interface DWKeysOverviewViewController ()
@property (strong, nonatomic) IBOutlet UILabel *operatorKeysDetailLabel;
@property (strong, nonatomic) IBOutlet UILabel *ownerKeysDetailLabel;
@property (strong, nonatomic) IBOutlet UILabel *votingKeysDetailLabel;

@end

@implementation DWKeysOverviewViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
    
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"MasternodeKeys" bundle:nil];
    DWKeysOverviewViewController *controller = [storyboard instantiateViewControllerWithIdentifier:@"KeysOverviewViewControllerIdentifier"];
    
    return controller;
}

@end
