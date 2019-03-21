//
//  DWMasternodeDetailViewController.m
//  DashWallet
//
//  Created by Sam Westrich on 2/21/19.
//  Copyright © 2019 Dash Core Group. All rights reserved.
//

#import "DWMasternodeDetailViewController.h"
#import "DSSimplifiedMasternodeEntry.h"
#import "DSLocalMasternode.h"
#import "DWUpdateMasternodeServiceViewController.h"
#import "DWUpdateMasternodeRegistrarViewController.h"
#import "DWReclaimMasternodeViewController.h"
#import "DWProviderUpdateRegistrarTransactionsViewController.h"
#import "DWProviderUpdateServiceTransactionsViewController.h"
#import <arpa/inet.h>
#import "BRCopyLabel.h"
#import "DWEnvironment.h"

@interface DWMasternodeDetailViewController ()
@property (strong, nonatomic) IBOutlet UILabel *locationLabel;
@property (strong, nonatomic) IBOutlet UILabel *operatorKeyLabel;
@property (strong, nonatomic) IBOutlet UILabel *operatorPublicKeyLabel;
@property (strong, nonatomic) IBOutlet UILabel *ownerKeyLabel;
@property (strong, nonatomic) IBOutlet UILabel *votingKeyLabel;
@property (strong, nonatomic) IBOutlet UILabel *votingAddressLabel;
@property (strong, nonatomic) IBOutlet UILabel *fundsInHoldingLabel;
@property (strong, nonatomic) IBOutlet UILabel *activeLabel;
@property (strong, nonatomic) IBOutlet UILabel *payToAddress;
@property (strong, nonatomic) IBOutlet BRCopyLabel *proRegTxLabel;
@property (strong, nonatomic) IBOutlet BRCopyLabel *proUpRegTxLabel;
@property (strong, nonatomic) IBOutlet BRCopyLabel *proUpServTxLabel;
@property (strong, nonatomic) DSChain * chain;

@end

@implementation DWMasternodeDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    char s[INET6_ADDRSTRLEN];
    uint32_t ipAddress = self.simplifiedMasternodeEntry.address.u32[3];
    
    self.locationLabel.text = [NSString stringWithFormat:@"%s:%d",inet_ntop(AF_INET, &ipAddress, s, sizeof(s)),self.simplifiedMasternodeEntry.port];
    self.ownerKeyLabel.text = self.localMasternode.ownerKeysWallet?@"SHOW":@"NO";
    self.operatorKeyLabel.text = self.localMasternode.operatorKeysWallet?@"SHOW":@"NO";
    self.operatorPublicKeyLabel.text = uint384_hex(self.simplifiedMasternodeEntry.operatorPublicKey);
    self.votingAddressLabel.text = self.simplifiedMasternodeEntry.votingAddress;
    self.votingKeyLabel.text = self.localMasternode.votingKeysWallet?@"SHOW":@"NO";
    self.fundsInHoldingLabel.text = self.localMasternode.holdingKeysWallet?@"YES":@"NO";
    self.activeLabel.text = self.simplifiedMasternodeEntry.isValid?@"YES":@"NO";
    self.payToAddress.text = self.localMasternode.payoutAddress?self.localMasternode.payoutAddress:@"Unknown";
    self.proRegTxLabel.text = uint256_hex(self.localMasternode.providerRegistrationTransaction.txHash);
    self.proUpRegTxLabel.text = [NSString stringWithFormat:@"%lu",(unsigned long)self.localMasternode.providerUpdateRegistrarTransactions.count];
    self.proUpServTxLabel.text = [NSString stringWithFormat:@"%lu",(unsigned long)self.localMasternode.providerUpdateServiceTransactions.count];
    self.chain = [DWEnvironment sharedInstance].currentChain;
}

-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"UpdateMasternodeServiceSegue"]) {
        UINavigationController * navigationController = (UINavigationController*)segue.destinationViewController;
        DWUpdateMasternodeServiceViewController * updateMasternodeServiceViewController = (DWUpdateMasternodeServiceViewController*)navigationController.topViewController;
        updateMasternodeServiceViewController.localMasternode = self.localMasternode;
    } else if ([segue.identifier isEqualToString:@"UpdateMasternodeRegistrarSegue"]) {
        UINavigationController * navigationController = (UINavigationController*)segue.destinationViewController;
        DWUpdateMasternodeRegistrarViewController * updateMasternodeRegistrarViewController = (DWUpdateMasternodeRegistrarViewController*)navigationController.topViewController;
        updateMasternodeRegistrarViewController.localMasternode = self.localMasternode;
        updateMasternodeRegistrarViewController.simplifiedMasternodeEntry = self.simplifiedMasternodeEntry;
    } else if ([segue.identifier isEqualToString:@"ReclaimMasternodeSegue"]) {
        UINavigationController * navigationController = (UINavigationController*)segue.destinationViewController;
        DWReclaimMasternodeViewController * reclaimMasternodeViewController = (DWReclaimMasternodeViewController*)navigationController.topViewController;
        reclaimMasternodeViewController.localMasternode = self.localMasternode;
    } else if ([segue.identifier isEqualToString:@"ShowProviderUpdateRegistrarTransactionsSegue"]) {
        DWProviderUpdateRegistrarTransactionsViewController * providerUpdateRegistrarTransactionsViewController = segue.destinationViewController;
        providerUpdateRegistrarTransactionsViewController.localMasternode = self.localMasternode;
    } else if ([segue.identifier isEqualToString:@"ShowProviderUpdateServiceTransactionsSegue"]) {
        DWProviderUpdateServiceTransactionsViewController * providerUpdateServiceTransactionsViewController = segue.destinationViewController;
        providerUpdateServiceTransactionsViewController.localMasternode = self.localMasternode;
    }
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 0:
        {
            switch (indexPath.row) {
                case 2:
                    if (self.localMasternode.ownerKeysWallet && [self.ownerKeyLabel.text isEqualToString:@"SHOW"]) {
                        [self.localMasternode.ownerKeysWallet seedWithPrompt:@"Show owner key?" forAmount:0 completion:^(NSData * _Nullable seed, BOOL cancelled) {
                            if (seed) {
                                self.ownerKeyLabel.text = [[self.localMasternode ownerKeyFromSeed:seed] privateKeyStringForChain:self.chain];
                            }
                        }];
                    }
                    break;
                case 3:
                    if (self.localMasternode.operatorKeysWallet && [self.operatorKeyLabel.text isEqualToString:@"SHOW"]) {
                        [self.localMasternode.operatorKeysWallet seedWithPrompt:@"Show operator key?" forAmount:0 completion:^(NSData * _Nullable seed, BOOL cancelled) {
                            if (seed) {
                                self.operatorKeyLabel.text = [self.localMasternode operatorKeyStringFromSeed:seed];
                            }
                        }];
                    }
                    break;
                case 4:
                    if (self.localMasternode.operatorKeysWallet && [self.votingKeyLabel.text isEqualToString:@"SHOW"]) {
                        [self.localMasternode.operatorKeysWallet seedWithPrompt:@"Show voting key?" forAmount:0 completion:^(NSData * _Nullable seed, BOOL cancelled) {
                            if (seed) {
                                self.votingKeyLabel.text = [[self.localMasternode votingKeyFromSeed:seed] privateKeyStringForChain:self.chain];
                            }
                        }];
                    }
                    break;
                    
                default:
                    break;
            }
            
        }
            break;
        case 1: {
            switch (indexPath.row) {
                case 0: {
                    if (!self.localMasternode) {
                        [self claimSimplifiedMasternodeEntry];
                    }
                }
                default:
                    break;
            }
        }
        default:
            break;
    }
}

-(void)claimSimplifiedMasternodeEntry {
    [[DSInsightManager sharedInstance] queryInsightForTransactionWithHash:[NSData dataWithUInt256: self.simplifiedMasternodeEntry.providerRegistrationTransactionHash].reverse.UInt256 onChain:self.simplifiedMasternodeEntry.chain completion:^(DSTransaction *transaction, NSError *error) {
        if ([transaction isKindOfClass:[DSProviderRegistrationTransaction class]]) {
            DSProviderRegistrationTransaction * providerRegistrationTransaction = (DSProviderRegistrationTransaction *)transaction;
            DSLocalMasternode * localMasternode = [self.simplifiedMasternodeEntry.chain.chainManager.masternodeManager localMasternodeFromProviderRegistrationTransaction:providerRegistrationTransaction save:TRUE];
        }
    }];
    
    
//    [self.moc performBlockAndWait:^{ // add the transaction to core data
//        [DSChainEntity setContext:self.moc];
//        Class transactionEntityClass = [transaction entityClass];
//        [transactionEntityClass setContext:self.moc];
//        [DSTransactionHashEntity setContext:self.moc];
//        [DSAddressEntity setContext:self.moc];
//        if ([DSTransactionEntity countObjectsMatching:@"transactionHash.txHash == %@", uint256_data(txHash)] == 0) {
//
//            DSTransactionEntity * transactionEntity = [transactionEntityClass managedObject];
//            [transactionEntity setAttributesFromTransaction:transaction];
//            [transactionEntityClass saveContext];
//        }
//    }];

//    uint32_t votingIndex;
//    DSWallet * votingWallet = [self.simplifiedMasternodeEntry.chain walletHavingProviderVotingAuthenticationHash:self.simplifiedMasternodeEntry.keyIDVoting foundAtIndex:&votingIndex];
//
//    uint32_t operatorIndex;
//    DSWallet * operatorWallet = [self.simplifiedMasternodeEntry.chain walletHavingProviderOperatorAuthenticationKey:self.simplifiedMasternodeEntry.operatorPublicKey foundAtIndex:&operatorIndex];
//
    
}


@end
