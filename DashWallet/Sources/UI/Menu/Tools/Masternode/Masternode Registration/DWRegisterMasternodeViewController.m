//
//  DWRegisterMasternodeViewController.m
//  DashWallet
//
//  Created by Sam Westrich on 2/9/19.
//  Copyright © 2019 Dash Core Group. All rights reserved.
//

#import "DWRegisterMasternodeViewController.h"
#import "DWEnvironment.h"
#import "DWFormTableViewController.h"
#import "DWKeyValueFormTableViewCell.h"
#import "DWMasternodeRegistrationModel.h"
#import "DWPublicKeyGenerationTableViewCell.h"
#import "DWSignPayloadModel.h"
#import "DWSignPayloadViewController.h"
#import "DWUIKit.h"

#define INPUT_CELL_HEIGHT 75
#define PUBLIC_KEY_CELL_HEIGHT 150

typedef NS_ENUM(NSUInteger, DWMasternodeRegistrationCell) {
    DWMasternodeRegistrationCell_CollateralTx,
    DWMasternodeRegistrationCell_CollateralIndex,
    DWMasternodeRegistrationCell_IPAddress,
    DWMasternodeRegistrationCell_Port,
    DWMasternodeRegistrationCell_PayoutAddress,
    DWMasternodeRegistrationCell_OwnerKey,
    DWMasternodeRegistrationCell_OperatorKey,
    DWMasternodeRegistrationCell_VotingKey,
    _DWMasternodeRegistrationCell_Count,
};

typedef NS_ENUM(NSUInteger, DWMasternodeRegistrationCellType) {
    DWMasternodeRegistrationCellType_InputValue,
    DWMasternodeRegistrationCellType_PublicKey,
};

@interface DWRegisterMasternodeViewController ()

@property (null_resettable, nonatomic, strong) DWMasternodeRegistrationModel *model;
@property (nonatomic, strong) DWActionFormCellModel *registerActionModel;
@property (nonatomic, strong) DWFormTableViewController *formController;

@end

@implementation DWRegisterMasternodeViewController

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
        self.title = NSLocalizedString(@"Registration", nil);
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (DWMasternodeRegistrationModel *)model {
    if (_model == nil) {
        _model = [[DWMasternodeRegistrationModel alloc] initForAccount:[DWEnvironment sharedInstance].currentAccount];
    }

    return _model;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    DWFormTableViewController *formController = [[DWFormTableViewController alloc] initWithStyle:UITableViewStylePlain];
    [formController setSections:[self sections] placeholderText:nil];

    [self addChildViewController:formController];
    formController.view.frame = self.view.bounds;
    formController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:formController.view];
    [formController didMoveToParentViewController:self];
    self.formController = formController;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - Data Source

- (NSString *)titleForCellAtRow:(NSUInteger)row {
    switch (row) {
        case DWMasternodeRegistrationCell_CollateralTx:
            return NSLocalizedString(@"Collateral Tx", nil);
        case DWMasternodeRegistrationCell_CollateralIndex:
            return NSLocalizedString(@"Collateral Index", nil);
        case DWMasternodeRegistrationCell_IPAddress:
            return NSLocalizedString(@"IP Address", nil);
        case DWMasternodeRegistrationCell_Port:
            return NSLocalizedString(@"Port", nil);
        case DWMasternodeRegistrationCell_PayoutAddress:
            return NSLocalizedString(@"Payout Address", nil);
        case DWMasternodeRegistrationCell_OwnerKey:
            return NSLocalizedString(@"Owner Private Key", nil);
        case DWMasternodeRegistrationCell_OperatorKey:
            return NSLocalizedString(@"Operator Public Key", nil);
        case DWMasternodeRegistrationCell_VotingKey:
            return NSLocalizedString(@"Voting Public Key", nil);
    }
    return @"";
}

- (NSString *)placeholderForCellAtRow:(NSUInteger)row {
    switch (row) {
        case DWMasternodeRegistrationCell_CollateralTx:
            return NSLocalizedString(@"Enter Transaction Hash", nil);
        case DWMasternodeRegistrationCell_CollateralIndex:
            return NSLocalizedString(@"Enter Transaction Index", nil);
        case DWMasternodeRegistrationCell_IPAddress:
            return NSLocalizedString(@"Enter IP Address of Masternode", nil);
        case DWMasternodeRegistrationCell_Port:
            return NSLocalizedString(@"Enter Port of Masternode", nil);
        case DWMasternodeRegistrationCell_PayoutAddress:
            return NSLocalizedString(@"Enter Payout Address", nil);
        case DWMasternodeRegistrationCell_OwnerKey:
            return NSLocalizedString(@"Enter Owner Private Key", nil);
        case DWMasternodeRegistrationCell_OperatorKey:
            return NSLocalizedString(@"Enter Operator Public Key", nil);
        case DWMasternodeRegistrationCell_VotingKey:
            return NSLocalizedString(@"Enter Voting Public Key", nil);
    }
    return @"";
}

- (NSString *)actionForCellAtRow:(NSUInteger)row {
    switch (row) {
        case DWMasternodeRegistrationCell_CollateralIndex:
            return NSLocalizedString(@"Lookup", nil);
        case DWMasternodeRegistrationCell_Port:
            return NSLocalizedString(@"Default", nil);
        case DWMasternodeRegistrationCell_PayoutAddress:
            return NSLocalizedString(@"Use Wallet", nil);
        case DWMasternodeRegistrationCell_OwnerKey:
            return NSLocalizedString(@"Use Wallet", nil);
        case DWMasternodeRegistrationCell_OperatorKey:
            return NSLocalizedString(@"Use Wallet", nil);
        case DWMasternodeRegistrationCell_VotingKey:
            return NSLocalizedString(@"Use Wallet", nil);
        default:
            return nil;
    }
}

- (void (^)(void))actionBlockForModel:(DWKeyValueFormCellModel *)model forCellAtRow:(NSUInteger)row {
    __weak __typeof(self) weakSelf = self;
    __weak __typeof(model) weakModel = model;
    switch (row) {
        case DWMasternodeRegistrationCell_CollateralIndex:
            return ^{
                __strong __typeof(weakSelf) strongSelf = weakSelf;

                if (!strongSelf) {
                    return;
                }
                [[strongSelf.formController.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:DWMasternodeRegistrationCell_CollateralTx inSection:0]] resignFirstResponder];
                [strongSelf.model lookupIndexesForCollateralHash:strongSelf.model.collateral.hash
                                                      completion:^(DSTransaction *_Nonnull transaction, NSIndexSet *_Nonnull indexSet, NSError *_Nonnull error) {
                                                          __strong __typeof(weakModel) strongModel = weakModel;
                                                          if (!strongModel) {
                                                              return;
                                                          }
                                                          if (error) {
                                                              //todo display error message
                                                          }
                                                          else if ([indexSet count] == 0) {
                                                          }
                                                          else {
                                                              strongModel.valueText = [NSString stringWithFormat:@"%lu", (unsigned long)[indexSet firstIndex]];
                                                          }
                                                      }];
            };
        case DWMasternodeRegistrationCell_Port:
            return ^{
                __strong __typeof(weakModel) strongModel = weakModel;
                if (!strongModel) {
                    return;
                }
                strongModel.valueText = [NSString stringWithFormat:@"%d", [DWEnvironment sharedInstance].currentChain.standardPort];
            };
        case DWMasternodeRegistrationCell_PayoutAddress:
            return ^{
                __strong __typeof(weakModel) strongModel = weakModel;
                if (!strongModel) {
                    return;
                }
                strongModel.valueText = [[DWEnvironment sharedInstance].currentAccount receiveAddress];
            };
        case DWMasternodeRegistrationCell_OwnerKey:
            return ^{
                __strong __typeof(weakModel) strongModel = weakModel;
                if (!strongModel) {
                    return;
                }
                @autoreleasepool {
                    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
                    DSDerivationPathFactory *factory = [DSDerivationPathFactory sharedInstance];
                    DSAuthenticationKeysDerivationPath *ownerDerivationPath = [factory providerOwnerKeysDerivationPathForWallet:wallet];
                    NSData *seed = [[DSBIP39Mnemonic sharedInstance] deriveKeyFromPhrase:wallet.seedPhraseIfAuthenticated
                                                                          withPassphrase:nil];
                    DSKey *key = [ownerDerivationPath firstUnusedPrivateKeyFromSeed:seed];
                    if ([key isKindOfClass:[DSECDSAKey class]]) {
                        strongModel.valueText = [((DSECDSAKey *)key) privateKeyStringForChain:ownerDerivationPath.chain];
                    }
                    else {
                        strongModel.valueText = key.secretKeyString;
                    }
                }
            };
        case DWMasternodeRegistrationCell_OperatorKey:
            return ^{
                __strong __typeof(weakModel) strongModel = weakModel;
                if (!strongModel) {
                    return;
                }
                DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
                DSDerivationPathFactory *factory = [DSDerivationPathFactory sharedInstance];
                DSAuthenticationKeysDerivationPath *operatorDerivationPath = [factory providerOperatorKeysDerivationPathForWallet:wallet];
                NSData *key = [operatorDerivationPath firstUnusedPublicKey];
                strongModel.valueText = key.hexString;
            };
        case DWMasternodeRegistrationCell_VotingKey:
            return ^{
                __strong __typeof(weakModel) strongModel = weakModel;
                if (!strongModel) {
                    return;
                }
                DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
                DSDerivationPathFactory *factory = [DSDerivationPathFactory sharedInstance];
                DSAuthenticationKeysDerivationPath *voterDerivationPath = [factory providerVotingKeysDerivationPathForWallet:wallet];
                NSData *key = [voterDerivationPath firstUnusedPublicKey];
                strongModel.valueText = key.hexString;
            };
        default:
            return nil;
    }
}

- (DWBaseFormCellModel *)modelForRow:(NSUInteger)row {
    NSString *actionText = [self actionForCellAtRow:row];
    DWKeyValueFormCellModel *model = [[DWKeyValueFormCellModel alloc] initWithTitle:[self titleForCellAtRow:row] valueText:@"" placeholderText:[self placeholderForCellAtRow:row] actionText:actionText ? [[NSAttributedString alloc] initWithString:actionText] : nil];
    if (actionText) {
        model.actionBlock = [self actionBlockForModel:model forCellAtRow:row];
    }
    __weak __typeof(self.model) weakModel = self.model;
    switch (row) {
        case DWMasternodeRegistrationCell_CollateralTx: {
            [model mvvm_observe:DW_KEYPATH(model, valueText)
                           with:^(__typeof(self) self, NSString *value) {
                               __strong __typeof(weakModel) strongModel = weakModel;
                               if (!strongModel) {
                                   return;
                               }
                               strongModel.collateral = ((DSUTXO){.hash = [value hexToData].UInt256, .n = strongModel.collateral.n});
                           }];
            break;
        }
        case DWMasternodeRegistrationCell_CollateralIndex: {
            [model mvvm_observe:DW_KEYPATH(model, valueText)
                           with:^(__typeof(self) self, NSString *value) {
                               __strong __typeof(weakModel) strongModel = weakModel;
                               if (!strongModel) {
                                   return;
                               }
                               strongModel.collateral = ((DSUTXO){.hash = strongModel.collateral.hash, .n = [value intValue]});
                           }];
            break;
        }
        case DWMasternodeRegistrationCell_IPAddress: {
            [model mvvm_observe:DW_KEYPATH(model, valueText)
                           with:^(__typeof(self) self, NSString *value) {
                               __strong __typeof(weakModel) strongModel = weakModel;
                               if (!strongModel) {
                                   return;
                               }
                               [strongModel setIpAddressFromString:value];
                           }];
            break;
        }
        case DWMasternodeRegistrationCell_Port: {
            [model mvvm_observe:DW_KEYPATH(model, valueText)
                           with:^(__typeof(self) self, NSString *value) {
                               __strong __typeof(weakModel) strongModel = weakModel;
                               if (!strongModel) {
                                   return;
                               }
                               strongModel.port = value.intValue;
                           }];
            break;
        }
        case DWMasternodeRegistrationCell_PayoutAddress: {
            [model mvvm_observe:DW_KEYPATH(model, valueText)
                           with:^(__typeof(self) self, NSString *value) {
                               __strong __typeof(weakModel) strongModel = weakModel;
                               if (!strongModel) {
                                   return;
                               }
                               strongModel.payoutAddress = value;
                           }];
            break;
        }
        case DWMasternodeRegistrationCell_OwnerKey: {
            [model mvvm_observe:DW_KEYPATH(model, valueText)
                           with:^(__typeof(self) self, NSString *value) {
                               __strong __typeof(weakModel) strongModel = weakModel;
                               if (!strongModel) {
                                   return;
                               }
                               strongModel.ownerKey = [DSECDSAKey keyWithPrivateKey:value onChain:[[DWEnvironment sharedInstance] currentChain]];
                           }];
            break;
        }
        case DWMasternodeRegistrationCell_OperatorKey: {
            [model mvvm_observe:DW_KEYPATH(model, valueText)
                           with:^(__typeof(self) self, NSString *value) {
                               __strong __typeof(weakModel) strongModel = weakModel;
                               if (!strongModel) {
                                   return;
                               }
                               strongModel.operatorKey = [DSBLSKey blsKeyWithPublicKey:[value hexToData].UInt384 onChain:[[DWEnvironment sharedInstance] currentChain]];
                           }];
            break;
        }
        case DWMasternodeRegistrationCell_VotingKey: {
            [model mvvm_observe:DW_KEYPATH(model, valueText)
                           with:^(__typeof(self) self, NSString *value) {
                               __strong __typeof(weakModel) strongModel = weakModel;
                               if (!strongModel) {
                                   return;
                               }
                               strongModel.votingKey = [DSECDSAKey keyWithPublicKey:[value hexToData]];
                           }];
            break;
        }
    }

    return model;
}

- (NSArray<DWBaseFormCellModel *> *)items {
    __weak typeof(self) weakSelf = self;

    NSMutableArray<DWBaseFormCellModel *> *items = [NSMutableArray array];

    for (NSUInteger i = 0; i < _DWMasternodeRegistrationCell_Count; i++) {
        [items addObject:[self modelForRow:i]];
    }
    return items;
}

- (DWBaseFormCellModel *)registerActionModel {
    DWActionFormCellModel *registerModel = [[DWActionFormCellModel alloc] initWithTitle:NSLocalizedString(@"View Signing Info", nil)];
    registerModel.didSelectBlock = ^(DWActionFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
        [self.model findCollateralTransactionWithCompletion:^(NSError *_Nonnull error) {
            if (error) {
                return;
            }
            [self.model registerMasternode:self
                    requestsPayloadSigning:^{
                        [self showPayloadSigning];
                    }
                                completion:^(NSError *_Nonnull error){

                                }];
            [self showPayloadSigning];
        }];
    };
    self.registerActionModel = registerModel;
    return registerModel;
}

- (NSArray<DWFormSectionModel *> *)sections {
    DWFormSectionModel *section = [[DWFormSectionModel alloc] init];
    section.items = [self items];

    DWFormSectionModel *registerSection = [[DWFormSectionModel alloc] init];
    registerSection.items = @[ [self registerActionModel] ];

    return @[ section, registerSection ];
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

- (void)showPayloadSigning {
    DWSignPayloadModel *signPayloadModel = [[DWSignPayloadModel alloc] initForCollateralAddress:self.model.collateralTransaction.outputAddresses[self.model.providerRegistrationTransaction.collateralOutpoint.n] withPayloadCollateralString:self.model.providerRegistrationTransaction.payloadCollateralString];
    DWSignPayloadViewController *signPayloadViewController = [[DWSignPayloadViewController alloc] initWithModel:signPayloadModel];
    __weak __typeof(self.model) weakModel = self.model;
    __weak __typeof(self) weakSelf = self;
    [signPayloadModel mvvm_observe:DW_KEYPATH(signPayloadModel, signature)
                              with:^(__typeof(self) self, NSData *signature) {
                                  __strong __typeof(weakModel) strongModel = weakModel;
                                  __strong __typeof(weakSelf) strongSelf = weakSelf;
                                  if (!strongSelf || !strongModel) {
                                      return;
                                  }
                                  strongModel.providerRegistrationTransaction.payloadSignature = signature;
                                  strongSelf.registerActionModel.title = NSLocalizedString(@"Register", nil);
                                  strongSelf.registerActionModel.didSelectBlock = ^(DWActionFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
                                      [strongModel signTransactionInputsWithCompletion:^(NSError *_Nonnull error) {
                                          __strong __typeof(weakSelf) strongSelf = weakSelf;
                                          if (!strongSelf) {
                                              return;
                                          }
                                          [strongSelf.navigationController popViewControllerAnimated:YES];
                                      }];
                                  };
                              }];
    [self.navigationController pushViewController:signPayloadViewController animated:YES];
}


@end
