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

#import "DWDerivationPathKeysViewController.h"
#import <DashSync/DSAuthenticationKeysDerivationPath.h>
#import <DashSync/DSDerivationPathFactory.h>
#import <DashSync/DashSync.h>

static NSString *const OwnerKeysSegueId = @"OwnerKeysSegue";
static NSString *const VotingKeysSegueId = @"VotingKeysSegue";
static NSString *const OperatorKeysSegueId = @"OperatorKeysSegue";

@interface DWKeysOverviewViewController ()

@property (strong, nonatomic) IBOutlet UILabel *ownerKeysTitleLabel;
@property (strong, nonatomic) IBOutlet UILabel *votingKeysTitleLabel;
@property (strong, nonatomic) IBOutlet UILabel *operatorKeysTitleLabel;
@property (strong, nonatomic) IBOutlet UILabel *ownerKeysDetailLabel;
@property (strong, nonatomic) IBOutlet UILabel *votingKeysDetailLabel;
@property (strong, nonatomic) IBOutlet UILabel *operatorKeysDetailLabel;

@property (strong, nonatomic) DSAuthenticationKeysDerivationPath *ownerDerivationPath;
@property (strong, nonatomic) DSAuthenticationKeysDerivationPath *votingDerivationPath;
@property (strong, nonatomic) DSAuthenticationKeysDerivationPath *operatorDerivationPath;

@end

@implementation DWKeysOverviewViewController


+ (instancetype)controller {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Masternode" bundle:nil];
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
    self.operatorDerivationPath = [factory providerOperatorKeysDerivationPathForWallet:wallet];

    self.tableView.tableFooterView = [[UIView alloc] init];

    self.ownerKeysTitleLabel.text = NSLocalizedString(@"Owner Keys", nil);
    self.votingKeysTitleLabel.text = NSLocalizedString(@"Voting Keys", nil);
    self.operatorKeysTitleLabel.text = NSLocalizedString(@"Operator Keys", nil);
    self.ownerKeysDetailLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%ld used", nil),
                                                                self.ownerDerivationPath.usedAddresses.count];
    self.votingKeysDetailLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%ld used", nil),
                                                                 self.votingDerivationPath.usedAddresses.count];
    self.operatorKeysDetailLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%ld used", nil),
                                                                   self.operatorDerivationPath.usedAddresses.count];
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
    else if ([segue.identifier isEqualToString:OperatorKeysSegueId]) {
        derivationPath = self.operatorDerivationPath;
        title = NSLocalizedString(@"Operator Keys", nil);
    }
    NSParameterAssert(derivationPath);
    DWDerivationPathKeysViewController *controller = (DWDerivationPathKeysViewController *)segue.destinationViewController;
    controller.derivationPath = derivationPath;
    controller.title = title;
}

@end
