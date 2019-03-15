//
//  DWReclaimMasternodeViewController.m
//  DashWallet
//
//  Created by Sam Westrich on 2/28/19.
//  Copyright © 2019 Dash Core Group. All rights reserved.
//

#import "DWReclaimMasternodeViewController.h"
#import "DWKeyValueTableViewCell.h"
#import "DWEnvironment.h"
#include <arpa/inet.h>

@interface DWReclaimMasternodeViewController ()

@property (nonatomic,strong) DSAccount * account;

@end

@implementation DWReclaimMasternodeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.account = [DWEnvironment sharedInstance].currentAccount;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 0;
}

-(UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 0:
        {
            switch (indexPath.row) {
                case 0:
                    return nil;
            }
        }
    }
    return nil;
}

-(IBAction)reclaimMasternode:(id)sender {
    [self.localMasternode reclaimTransactionToAccount:self.account completion:^(DSTransaction * _Nonnull reclaimTransaction) {
        if (reclaimTransaction) {
            DSMasternodeHoldingsDerivationPath * derivationPath = [[DSDerivationPathFactory sharedInstance] providerFundsDerivationPathForWallet:self.localMasternode.holdingKeysWallet];
            [derivationPath signTransaction:reclaimTransaction withPrompt:@"Would you like to update this masternode?" completion:^(BOOL signedTransaction) {
                if (signedTransaction) {
                    [self.localMasternode.providerRegistrationTransaction.chain.chainManager.transactionManager publishTransaction:reclaimTransaction completion:^(NSError * _Nullable error) {
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
            [self raiseIssue:@"Error" message:@"Unable to create Reclaim Transaction."];
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
