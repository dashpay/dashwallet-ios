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

#import "DWDerivationPathKeysViewController.h"

#import <DashSync/DashSync.h>
#import <DashSync/DSAuthenticationKeysDerivationPath.h>

static NSString * const KeyInfoCellId = @"KeyInfoCell";
static NSString * const LoadMoreCellId = @"LoadMoreCell";

typedef NS_ENUM(NSUInteger, DWDerivationPathInfo) {
    DWDerivationPathInfoAddress,
    DWDerivationPathInfoPublicKey,
    DWDerivationPathInfoPrivateKey,
    _DWDerivationPathInfo_Count,
};

@interface DWDerivationPathKeysViewController ()

@property (nonatomic, assign) NSInteger visibleIndexes;

@end

@implementation DWDerivationPathKeysViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.tableView.tableFooterView = [[UIView alloc] init];
    
    self.visibleIndexes = 1;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.visibleIndexes + 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == self.visibleIndexes) {
        return 1;
    }
    else {
        return _DWDerivationPathInfo_Count;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == self.visibleIndexes) {
        return @"";
    }
    else {
        return [NSString stringWithFormat:@"%ld", section];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == self.visibleIndexes) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:LoadMoreCellId forIndexPath:indexPath];
        cell.textLabel.text = NSLocalizedString(@"Load more", nil);
        return cell;
    }
    else {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:KeyInfoCellId forIndexPath:indexPath];
        
        DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
        NSInteger index = indexPath.section;
        DWDerivationPathInfo info = indexPath.row;
        switch (info) {
            case DWDerivationPathInfoAddress: {
                cell.textLabel.text = NSLocalizedString(@"Address", nil);
                cell.detailTextLabel.text = [self.derivationPath addressAtIndex:index];
                
                break;
            }
            case DWDerivationPathInfoPublicKey: {
                cell.textLabel.text = NSLocalizedString(@"Public key", nil);
                cell.detailTextLabel.text = [self.derivationPath publicKeyDataAtIndex:index].hexString;
                
                break;
            }
            case DWDerivationPathInfoPrivateKey: {
                cell.textLabel.text = NSLocalizedString(@"Private key", nil);
                NSData *seed = [[DSBIP39Mnemonic sharedInstance] deriveKeyFromPhrase:wallet.seedPhraseIfAuthenticated withPassphrase:nil];
                DSKey *key = [self.derivationPath privateKeyAtIndex:index fromSeed:seed];
                cell.detailTextLabel.text = key.secretKeyString;
                break;
            }
            default:
                break;
        }
        
        return cell;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == self.visibleIndexes) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        
        self.visibleIndexes += 1;
        [tableView beginUpdates];
        [tableView insertSections:[NSIndexSet indexSetWithIndex:self.visibleIndexes - 1] withRowAnimation:UITableViewRowAnimationAutomatic];
        [tableView endUpdates];
        
        [tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:self.visibleIndexes - 1] atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
    }
}

@end
