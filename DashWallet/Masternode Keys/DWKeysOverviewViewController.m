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

#import <DashSync/DashSync.h>
#import <DashSync/DSDerivationPathFactory.h>
#import <DashSync/DSAuthenticationKeysDerivationPath.h>
#import "DWDerivationPathKeysViewController.h"

static NSString * const OwnerKeysSegueId = @"OwnerKeysSegue";
static NSString * const VotingKeysSegueId = @"VotingKeysSegue";

@interface DWKeysOverviewViewController ()

@property (strong, nonatomic) IBOutlet UILabel *ownerKeysTitleLabel;
@property (strong, nonatomic) IBOutlet UILabel *votingKeysTitleLabel;
@property (strong, nonatomic) IBOutlet UILabel *ownerKeysDetailLabel;
@property (strong, nonatomic) IBOutlet UILabel *votingKeysDetailLabel;

@property (strong, nonatomic) DSAuthenticationKeysDerivationPath *ownerDerivationPath;
@property (strong, nonatomic) DSAuthenticationKeysDerivationPath *votingDerivationPath;

@end

@implementation DWKeysOverviewViewController


+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"MasternodeKeys" bundle:nil];
    DWKeysOverviewViewController *controller = [storyboard instantiateViewControllerWithIdentifier:@"KeysOverviewViewControllerIdentifier"];
    
    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = NSLocalizedString(@"Wallet Keys", nil);
    
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSDerivationPathFactory *factory = [DSDerivationPathFactory sharedInstance];
    self.ownerDerivationPath = [factory providerOwnerKeysDerivationPathForWallet:wallet];
    self.votingDerivationPath = [factory providerVotingKeysDerivationPathForWallet:wallet];
    
    self.tableView.tableFooterView = [[UIView alloc] init];
    
    self.ownerKeysTitleLabel.text = NSLocalizedString(@"Owner Keys", nil);
    self.votingKeysTitleLabel.text = NSLocalizedString(@"Voting Keys", nil);
    self.ownerKeysDetailLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%ld used", nil),
                                      self.ownerDerivationPath.usedAddresses.count];
    self.votingKeysDetailLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%ld used", nil),
                                       self.votingDerivationPath.usedAddresses.count];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    DSAuthenticationKeysDerivationPath *derivationPath = nil;
    NSString *title = nil;
    if ([segue.identifier isEqualToString:OwnerKeysSegueId]) {
        derivationPath = self.ownerDerivationPath;
        title = NSLocalizedString(@"Owner Keys", nil);
    }
    else if ([segue.identifier isEqualToString:VotingKeysSegueId]) {
        derivationPath = self.votingDerivationPath;
        title = NSLocalizedString(@"Voting Keys", nil);
    }
    NSParameterAssert(derivationPath);
    DWDerivationPathKeysViewController *controller = (DWDerivationPathKeysViewController *)segue.destinationViewController;
    controller.derivationPath = derivationPath;
    controller.title = title;
}

@end
