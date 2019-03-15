//
//  DWUpdateMasternodeRegistrarViewController.m
//  DashWallet
//
//  Created by Sam Westrich on 2/22/19.
//  Copyright © 2019 Dash Core Group. All rights reserved.
//

#import "DWUpdateMasternodeRegistrarViewController.h"
#import "DWKeyValueTableViewCell.h"
#import "DWEnvironment.h"
#include <arpa/inet.h>

@interface DWUpdateMasternodeRegistrarViewController ()

@property (nonatomic,strong) DWKeyValueTableViewCell * payoutTableViewCell;
@property (nonatomic,strong) DSAccount * account;
@property (nonatomic,strong) DSWallet * votingWallet;

@end

@implementation DWUpdateMasternodeRegistrarViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.payoutTableViewCell = [self.tableView dequeueReusableCellWithIdentifier:@"MasternodePayoutAddressCellIdentifier"];
    self.votingWallet = [DWEnvironment sharedInstance].currentWallet;
    self.account = [DWEnvironment sharedInstance].currentAccount;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 3;
}

-(UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 0:
        {
            switch (indexPath.row) {
                case 0:
                    return self.payoutTableViewCell;
            }
        }
    }
    return nil;
}

-(IBAction)updateMasternode:(id)sender {
    UInt160 votingHash;
    if (self.votingWallet) {
        DSAuthenticationKeysDerivationPath * providerVotingKeysDerivationPath = [DSAuthenticationKeysDerivationPath providerVotingKeysDerivationPathForWallet:self.votingWallet];
        votingHash = providerVotingKeysDerivationPath.firstUnusedPublicKey.hash160;
    } else {
        votingHash = self.simplifiedMasternodeEntry.keyIDVoting;
    }
    NSString * payoutAddress = (self.payoutTableViewCell.valueTextField.text && ![self.payoutTableViewCell.valueTextField.text isEqualToString:@""])?self.payoutTableViewCell.valueTextField.text:self.localMasternode
    .payoutAddress;
    [self.localMasternode updateTransactionFundedByAccount:self.account changeOperator:self.localMasternode.providerRegistrationTransaction.operatorKey changeVotingKeyHash:votingHash changePayoutAddress:payoutAddress completion:^(DSProviderUpdateRegistrarTransaction * _Nonnull providerUpdateRegistrarTransaction) {
        
        if (providerUpdateRegistrarTransaction) {
            [self.account signTransaction:providerUpdateRegistrarTransaction withPrompt:@"Would you like to update this masternode?" completion:^(BOOL signedTransaction) {
                if (signedTransaction) {
                    [self.localMasternode.providerRegistrationTransaction.chain.chainManager.transactionManager publishTransaction:providerUpdateRegistrarTransaction completion:^(NSError * _Nullable error) {
                        if (error) {
                            [self raiseIssue:@"Error" message:error.localizedDescription];
                        } else {
                            //[masternode registerInWallet];
                            [self.presentingViewController dismissViewControllerAnimated:TRUE completion:nil];
                        }
                    }];
                } else {
                    [self raiseIssue:@"Error" message:@"Transaction was not signed."];
                }
            }];
        } else {
            [self raiseIssue:@"Error" message:@"Unable to create ProviderRegistrationTransaction."];
        }
    }];
}

-(void)raiseIssue:(NSString*)issue message:(NSString*)message {
    UIAlertController * alert = [UIAlertController alertControllerWithTitle:issue message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        
    }]];
    [self presentViewController:alert animated:TRUE completion:^{
        
    }];
}

-(IBAction)cancel {
    [self.presentingViewController dismissViewControllerAnimated:TRUE completion:nil];
}

@end
