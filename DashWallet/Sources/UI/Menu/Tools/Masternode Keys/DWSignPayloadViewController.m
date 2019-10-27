//
//  DWSignPayloadViewController.m
//  DashWallet
//
//  Created by Sam Westrich on 3/8/19.
//  Copyright © 2019 Dash Core Group. All rights reserved.
//

#import "DWSignPayloadViewController.h"
#import "DSAccount.h"
#import "DSECDSAKey.h"
#import "DSProviderRegistrationTransaction.h"
#import "DSWallet.h"
#import "NSData+Bitcoin.h"
#import "NSMutableData+Dash.h"
#import "NSString+Dash.h"

@interface DWSignPayloadViewController ()
@property (strong, nonatomic) IBOutlet UITextView *signatureMessageInputTextView;
@property (strong, nonatomic) IBOutlet UITextView *signatureMessageResultTextView;
@property (strong, nonatomic) IBOutlet UIButton *signButton;

@end

@implementation DWSignPayloadViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.signatureMessageInputTextView.text = [NSString stringWithFormat:@"signmessage %@ %@", self.collateralAddress, self.providerRegistrationTransaction.payloadCollateralString];

    if ([self.providerRegistrationTransaction.chain accountContainingAddress:self.collateralAddress]) {
        self.signButton.enabled = TRUE;
    }
    else {
        self.signButton.enabled = FALSE;
    }
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/
- (IBAction)sign:(id)sender {

    if (self.signatureMessageResultTextView.text && ![self.signatureMessageResultTextView.text isEqualToString:@""]) {
        NSData *signature = [[NSData alloc] initWithBase64EncodedString:self.signatureMessageResultTextView.text options:0];
        DSECDSAKey *key = [DSECDSAKey keyRecoveredFromCompactSig:signature andMessageDigest:self.providerRegistrationTransaction.payloadCollateralDigest];
        NSString *address = [key addressForChain:self.providerRegistrationTransaction.chain];
        if ([address isEqualToString:self.collateralAddress]) {
            [self.delegate viewController:self didReturnSignature:signature];
        }
        else {
            NSLog(@"Not matching signature");
        }
    }
    else {
        DSAccount *account = [self.providerRegistrationTransaction.chain accountContainingAddress:self.collateralAddress];


        DSFundsDerivationPath *derivationPath = [account derivationPathContainingAddress:self.collateralAddress];

        NSIndexPath *indexPath = [derivationPath indexPathForKnownAddress:self.collateralAddress];

        [account.wallet seedWithPrompt:@"Sign?"
                             forAmount:0
                            completion:^(NSData *_Nullable seed, BOOL cancelled) {
                                if (seed && !cancelled) {
                                    DSECDSAKey *key = (DSECDSAKey *)[derivationPath privateKeyAtIndexPath:indexPath fromSeed:seed];
                                    NSData *data = [key compactSign:self.providerRegistrationTransaction.payloadCollateralDigest];
                                    [self.delegate viewController:self didReturnSignature:data];
                                }
                            }];
    }
}

@end
