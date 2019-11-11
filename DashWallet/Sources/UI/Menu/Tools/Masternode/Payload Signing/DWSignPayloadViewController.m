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

@property (nonatomic, strong) DWSignPayloadModel *model;

@end

@implementation DWSignPayloadViewController

//- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
//    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
//        self.title = NSLocalizedString(@"External Sign", nil);
//        self.hidesBottomBarWhenPushed = YES;
//    }
//    return self;
//}

- (instancetype)initWithModel:(DWSignPayloadModel *)model {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _model = model;
    }
    return self;
}


- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupView];
}

+ (NSString *)actionButtonTitle {
    return NSLocalizedString(@"Verify Signature", nil);
}


- (void)setupView {
    self.title = NSLocalizedString(@"External Sign", nil);
    self.actionButton.enabled = YES;

    NSParameterAssert(self.model);

    DWSignPayloadView *contentView = [[DWSignPayloadView alloc] initWithModel:self.model];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    contentView.delegate = self;
    [self setupContentView:contentView];
    self.contentView = contentView;
}


- (void)setupObserving {
}

//- (IBAction)sign:(id)sender {
//
//    if (self.signatureMessageResultTextView.text && ![self.signatureMessageResultTextView.text isEqualToString:@""]) {
//        NSData *signature = [[NSData alloc] initWithBase64EncodedString:self.signatureMessageResultTextView.text options:0];
//        DSECDSAKey *key = [DSECDSAKey keyRecoveredFromCompactSig:signature andMessageDigest:self.providerRegistrationTransaction.payloadCollateralDigest];
//        NSString *address = [key addressForChain:self.providerRegistrationTransaction.chain];
//        if ([address isEqualToString:self.collateralAddress]) {
//            [self.delegate viewController:self didReturnSignature:signature];
//        }
//        else {
//            NSLog(@"Not matching signature");
//        }
//    }
//    else {
//        DSAccount *account = [self.providerRegistrationTransaction.chain accountContainingAddress:self.collateralAddress];
//
//
//        DSFundsDerivationPath *derivationPath = [account derivationPathContainingAddress:self.collateralAddress];
//
//        NSIndexPath *indexPath = [derivationPath indexPathForKnownAddress:self.collateralAddress];
//
//        [account.wallet seedWithPrompt:@"Sign?"
//                             forAmount:0
//                            completion:^(NSData *_Nullable seed, BOOL cancelled) {
//                                if (seed && !cancelled) {
//                                    DSECDSAKey *key = (DSECDSAKey *)[derivationPath privateKeyAtIndexPath:indexPath fromSeed:seed];
//                                    NSData *data = [key compactSign:self.providerRegistrationTransaction.payloadCollateralDigest];
//                                    [self.delegate viewController:self didReturnSignature:data];
//                                }
//                            }];
//    }
//}

@end
