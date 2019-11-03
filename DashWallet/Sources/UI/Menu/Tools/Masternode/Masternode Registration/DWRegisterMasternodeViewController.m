//
//  DWRegisterMasternodeViewController.m
//  DashWallet
//
//  Created by Sam Westrich on 2/9/19.
//  Copyright © 2019 Dash Core Group. All rights reserved.
//

#import "DWRegisterMasternodeViewController.h"
#import "DWEnvironment.h"
#import "DWKeyValueTableViewCell.h"
#import "DWMasternodeRegistrationModel.h"
#import "DWPublicKeyGenerationTableViewCell.h"
#import "DWSignPayloadViewController.h"
#import "DWUIKit.h"
#include <arpa/inet.h>

#define INPUT_CELL_HEIGHT 75
#define PUBLIC_KEY_CELL_HEIGHT 150

@interface DWRegisterMasternodeViewController ()

@property (nonatomic, strong) DWKeyValueTableViewCell *collateralTransactionTableViewCell;
@property (nonatomic, strong) DWKeyValueTableViewCell *collateralIndexTableViewCell;
@property (nonatomic, strong) DWKeyValueTableViewCell *ipAddressTableViewCell;
@property (nonatomic, strong) DWKeyValueTableViewCell *portTableViewCell;
@property (nonatomic, strong) DWKeyValueTableViewCell *payToAddressTableViewCell;
@property (nonatomic, strong) DWPublicKeyGenerationTableViewCell *ownerIndexTableViewCell;
@property (nonatomic, strong) DWPublicKeyGenerationTableViewCell *operatorIndexTableViewCell;
@property (nonatomic, strong) DWPublicKeyGenerationTableViewCell *votingIndexTableViewCell;
@property (nonatomic, strong) DSAccount *account;
@property (nonatomic, strong) DSWallet *wallet;
@property (nonatomic, strong) DSProviderRegistrationTransaction *providerRegistrationTransaction;
@property (nonatomic, strong) DSTransaction *collateralTransaction;
@property (readonly, nonatomic, strong) DWMasternodeRegistrationModel *model;

@end

@implementation DWRegisterMasternodeViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    _model = [[DWMasternodeRegistrationModel alloc] initWithWallet:self.wallet];
    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    self.payToAddressTableViewCell = [self.tableView dequeueReusableCellWithIdentifier:@"MasternodePayoutAddressCellIdentifier"];
    self.collateralTransactionTableViewCell = [self.tableView dequeueReusableCellWithIdentifier:@"MasternodeCollateralTransactionCellIdentifier"];
    self.collateralIndexTableViewCell = [self.tableView dequeueReusableCellWithIdentifier:@"MasternodeCollateralIndexCellIdentifier"];
    self.ipAddressTableViewCell = [self.tableView dequeueReusableCellWithIdentifier:@"MasternodeIPAddressCellIdentifier"];
    self.portTableViewCell = [self.tableView dequeueReusableCellWithIdentifier:@"MasternodePortCellIdentifier"];
    self.portTableViewCell.valueTextField.text = [NSString stringWithFormat:@"%d", self.chain.standardPort];
    self.ownerIndexTableViewCell = [self.tableView dequeueReusableCellWithIdentifier:@"MasternodeOwnerIndexCellIdentifier"];
    self.votingIndexTableViewCell = [self.tableView dequeueReusableCellWithIdentifier:@"MasternodeVotingIndexCellIdentifier"];
    self.operatorIndexTableViewCell = [self.tableView dequeueReusableCellWithIdentifier:@"MasternodeOperatorIndexCellIdentifier"];
    self.wallet = [DWEnvironment sharedInstance].currentWallet;
    self.account = [DWEnvironment sharedInstance].currentAccount;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 8;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 0: {
            switch (indexPath.row) {
                case 0:
                    return INPUT_CELL_HEIGHT;
                case 1:
                    return INPUT_CELL_HEIGHT;
                case 2:
                    return INPUT_CELL_HEIGHT;
                case 3:
                    return INPUT_CELL_HEIGHT;
                case 4:
                    return PUBLIC_KEY_CELL_HEIGHT;
                case 5:
                    return PUBLIC_KEY_CELL_HEIGHT;
                case 6:
                    return PUBLIC_KEY_CELL_HEIGHT;
                case 7:
                    return INPUT_CELL_HEIGHT;
            }
        }
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 0: {
            switch (indexPath.row) {
                case 0:
                    return self.collateralTransactionTableViewCell;
                case 1:
                    return self.collateralIndexTableViewCell;
                case 2:
                    return self.ipAddressTableViewCell;
                case 3:
                    return self.portTableViewCell;
                case 4:
                    return self.ownerIndexTableViewCell;
                case 5:
                    return self.operatorIndexTableViewCell;
                case 6:
                    return self.votingIndexTableViewCell;
                case 7:
                    return self.payToAddressTableViewCell;
            }
        }
    }
    return nil;
}

- (void)signTransactionInputs:(DSProviderRegistrationTransaction *)providerRegistrationTransaction {
    [self.account signTransaction:providerRegistrationTransaction
                       withPrompt:@"Would you like to register this masternode?"
                       completion:^(BOOL signedTransaction, BOOL cancelled) {
                           if (signedTransaction) {
                               [self.chain.chainManager.transactionManager publishTransaction:providerRegistrationTransaction
                                                                                   completion:^(NSError *_Nullable error) {
                                                                                       if (error) {
                                                                                           [self raiseIssue:@"Error" message:error.localizedDescription];
                                                                                       }
                                                                                       else {
                                                                                           //[masternode registerInWallet];
                                                                                           [self.presentingViewController dismissViewControllerAnimated:TRUE completion:nil];
                                                                                       }
                                                                                   }];
                           }
                           else {
                               [self raiseIssue:@"Error" message:@"Transaction was not signed."];
                           }
                       }];
}

- (IBAction)registerMasternode:(id)sender {
    NSString *ipAddressString = [self.ipAddressTableViewCell.valueTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *portString = [self.portTableViewCell.valueTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    UInt128 ipAddress = {.u32 = {0, 0, CFSwapInt32HostToBig(0xffff), 0}};
    struct in_addr addrV4;
    if (inet_aton([ipAddressString UTF8String], &addrV4) != 0) {
        uint32_t ip = ntohl(addrV4.s_addr);
        ipAddress.u32[3] = CFSwapInt32HostToBig(ip);
        DSDLog(@"%08x", ip);
    }
    uint16_t port = [portString intValue];

    uint32_t ownerWalletIndex = UINT32_MAX;
    uint32_t votingWalletIndex = UINT32_MAX;
    uint32_t operatorWalletIndex = UINT32_MAX;

    if (self.ownerIndexTableViewCell.publicKeyTextField.text && ![self.ownerIndexTableViewCell.publicKeyTextField.text isEqualToString:@""]) {
        ownerWalletIndex = (uint32_t)[self.ownerIndexTableViewCell.publicKeyTextField.text integerValue];
    }

    if (self.operatorIndexTableViewCell.publicKeyTextField.text && ![self.operatorIndexTableViewCell.publicKeyTextField.text isEqualToString:@""]) {
        operatorWalletIndex = (uint32_t)[self.operatorIndexTableViewCell.publicKeyTextField.text integerValue];
    }

    if (self.votingIndexTableViewCell.publicKeyTextField.text && ![self.votingIndexTableViewCell.publicKeyTextField.text isEqualToString:@""]) {
        votingWalletIndex = (uint32_t)[self.votingIndexTableViewCell.publicKeyTextField.text integerValue];
    }

    DSLocalMasternode *masternode = [self.chain.chainManager.masternodeManager createNewMasternodeWithIPAddress:ipAddress onPort:port inFundsWallet:self.wallet fundsWalletIndex:UINT32_MAX inOperatorWallet:self.wallet operatorWalletIndex:operatorWalletIndex inOwnerWallet:self.wallet ownerWalletIndex:ownerWalletIndex inVotingWallet:self.wallet votingWalletIndex:votingWalletIndex];

    NSString *payoutAddress = [self.payToAddressTableViewCell.valueTextField.text isValidDashAddressOnChain:self.chain] ? self.payToAddressTableViewCell.textLabel.text : self.account.receiveAddress;


    DSUTXO collateral = DSUTXO_ZERO;
    UInt256 nonReversedCollateralHash = UINT256_ZERO;
    NSString *collateralTransactionHash = self.collateralTransactionTableViewCell.valueTextField.text;
    if (![collateralTransactionHash isEqual:@""]) {
        NSData *collateralTransactionHashData = [collateralTransactionHash hexToData];
        if (collateralTransactionHashData.length != 32)
            return;
        collateral.hash = collateralTransactionHashData.reverse.UInt256;

        nonReversedCollateralHash = collateralTransactionHashData.UInt256;
        collateral.n = [self.collateralIndexTableViewCell.valueTextField.text integerValue];
    }


    [masternode registrationTransactionFundedByAccount:self.account
                                             toAddress:payoutAddress
                                        withCollateral:collateral
                                            completion:^(DSProviderRegistrationTransaction *_Nonnull providerRegistrationTransaction) {
                                                if (providerRegistrationTransaction) {
                                                    if (dsutxo_is_zero(collateral)) {
                                                        [self signTransactionInputs:providerRegistrationTransaction];
                                                    }
                                                    else {
                                                        [[DSInsightManager sharedInstance] queryInsightForTransactionWithHash:nonReversedCollateralHash
                                                                                                                      onChain:self.chain
                                                                                                                   completion:^(DSTransaction *transaction, NSError *error) {
                                                                                                                       NSIndexSet *indexSet = [[transaction outputAmounts] indexesOfObjectsPassingTest:^BOOL(id _Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
                                                                                                                           if ([obj isEqual:@(MASTERNODE_COST)])
                                                                                                                               return TRUE;
                                                                                                                           return FALSE;
                                                                                                                       }];
                                                                                                                       if ([indexSet containsIndex:collateral.n]) {
                                                                                                                           self.collateralTransaction = transaction;
                                                                                                                           self.providerRegistrationTransaction = providerRegistrationTransaction;
                                                                                                                           dispatch_async(dispatch_get_main_queue(), ^{
                                                                                                                               [self performSegueWithIdentifier:@"PayloadSigningSegue" sender:self];
                                                                                                                           });
                                                                                                                       }
                                                                                                                       else {
                                                                                                                           dispatch_async(dispatch_get_main_queue(), ^{
                                                                                                                               [self raiseIssue:@"Error" message:@"Incorrect collateral index"];
                                                                                                                           });
                                                                                                                       }
                                                                                                                   }];
                                                    }
                                                }
                                                else {
                                                    [self raiseIssue:@"Error" message:@"Unable to create ProviderRegistrationTransaction."];
                                                }
                                            }];
}

- (void)raiseIssue:(NSString *)issue message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:issue message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Ok"
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *_Nonnull action){

                                            }]];
    [self presentViewController:alert
                       animated:TRUE
                     completion:^{

                     }];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"PayloadSigningSegue"]) {
        DWSignPayloadViewController *signPayloadSegue = (DWSignPayloadViewController *)segue.destinationViewController;
        signPayloadSegue.collateralAddress = self.collateralTransaction.outputAddresses[self.providerRegistrationTransaction.collateralOutpoint.n];
        signPayloadSegue.providerRegistrationTransaction = self.providerRegistrationTransaction;
        signPayloadSegue.delegate = self;
    }
}

- (void)viewController:(nonnull UIViewController *)controller didReturnSignature:(nonnull NSData *)signature {
    self.providerRegistrationTransaction.payloadSignature = signature;
    [self signTransactionInputs:self.providerRegistrationTransaction];
}


@end
