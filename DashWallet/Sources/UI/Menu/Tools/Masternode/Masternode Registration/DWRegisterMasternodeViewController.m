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

@property (nonatomic, strong) DSAccount *account;
@property (nonatomic, strong) DSProviderRegistrationTransaction *providerRegistrationTransaction;
@property (nonatomic, strong) DSTransaction *collateralTransaction;
@property (null_resettable, nonatomic, strong) DWMasternodeRegistrationModel *model;
@property (nonatomic, strong) DWFormTableViewController *formController;

@end

@implementation DWRegisterMasternodeViewController

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
        self.account = [DWEnvironment sharedInstance].currentAccount;
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
            return NSLocalizedString(@"Owner Public Key", nil);
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
            return NSLocalizedString(@"Enter Owner Public Key", nil);
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
        case DWMasternodeRegistrationCell_OwnerKey:
            return NSLocalizedString(@"Using Index 0", nil);
        case DWMasternodeRegistrationCell_OperatorKey:
            return NSLocalizedString(@"Using Index 0", nil);
        case DWMasternodeRegistrationCell_VotingKey:
            return NSLocalizedString(@"Using Index 0", nil);
        default:
            return nil;
    }
}

- (DWMasternodeRegistrationCellType)typeForCellAtRow:(NSUInteger)row {
    switch (row) {
        case DWMasternodeRegistrationCell_CollateralTx:
        case DWMasternodeRegistrationCell_CollateralIndex:
        case DWMasternodeRegistrationCell_IPAddress:
        case DWMasternodeRegistrationCell_Port:
        case DWMasternodeRegistrationCell_PayoutAddress:
            return DWMasternodeRegistrationCellType_InputValue;
        case DWMasternodeRegistrationCell_OwnerKey:
        case DWMasternodeRegistrationCell_OperatorKey:
        case DWMasternodeRegistrationCell_VotingKey:
            return DWMasternodeRegistrationCellType_PublicKey;
    }
    return DWMasternodeRegistrationCellType_InputValue;
}

- (DWBaseFormCellModel *)modelForRow:(NSUInteger)row {
    switch ([self typeForCellAtRow:row]) {
        case DWMasternodeRegistrationCellType_InputValue: {
            NSString *actionText = [self actionForCellAtRow:row];
            DWKeyValueFormCellModel *model = [[DWKeyValueFormCellModel alloc] initWithTitle:[self titleForCellAtRow:row] valueText:@"" placeholderText:[self placeholderForCellAtRow:row] actionText:actionText ? [[NSAttributedString alloc] initWithString:actionText] : nil];
            if (row == DWMasternodeRegistrationCell_Port) {
                __weak __typeof(model) weakModel = model;
                model.actionBlock = ^{
                    __strong __typeof(weakModel) strongModel = weakModel;
                    if (!strongModel) {
                        return;
                    }
                    strongModel.valueText = [NSString stringWithFormat:@"%d", [DWEnvironment sharedInstance].currentChain.standardPort];
                };
            } else if (row == DWMasternodeRegistrationCell_CollateralIndex) {
                __weak __typeof(self) weakSelf = self;
                __weak __typeof(model) weakModel = model;
                model.actionBlock = ^{
                    __strong __typeof(weakSelf) strongSelf = weakSelf;
                    
                    if (!strongSelf) {
                        return;
                    }
                    [strongSelf.model lookupIndexesForCollateralHash:strongSelf.model.collateral.hash completion:^(DSTransaction * _Nonnull transaction, NSIndexSet * _Nonnull indexSet, NSError * _Nonnull error) {
                        __strong __typeof(weakModel) strongModel = weakModel;
                        if (!strongModel) {
                            return;
                        }
                        strongModel.valueText = [NSString stringWithFormat:@"%lu",(unsigned long)[indexSet firstIndex]];
                    }];
                    
                };
            }
            return model;
        }
        case DWMasternodeRegistrationCellType_PublicKey: {
            NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
            attachment.image = [UIImage imageNamed:@"icon_disclosure_indicator"];

            NSAttributedString *attachmentString = [NSAttributedString attributedStringWithAttachment:attachment];
            NSMutableAttributedString *indexString = [[NSMutableAttributedString alloc] initWithString:[self actionForCellAtRow:row]];
            [indexString appendAttributedString:attachmentString];
            return [[DWKeyValueFormCellModel alloc] initWithTitle:[self titleForCellAtRow:row] valueText:@"" placeholderText:[self placeholderForCellAtRow:row] actionText:indexString];
        }
    }
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
    DWActionFormCellModel *registerModel = [[DWActionFormCellModel alloc] initWithTitle:NSLocalizedString(@"Register", nil)];
    registerModel.didSelectBlock = ^(DWActionFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
        [self showPayloadSigning];
    };
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
    DWSignPayloadViewController *signPayloadViewController = [[DWSignPayloadViewController alloc] init];
    signPayloadViewController.collateralAddress = self.collateralTransaction.outputAddresses[self.providerRegistrationTransaction.collateralOutpoint.n];
    signPayloadViewController.providerRegistrationTransaction = self.providerRegistrationTransaction;
    signPayloadViewController.delegate = self;
    [self.navigationController pushViewController:signPayloadViewController animated:YES];
}

- (void)viewController:(nonnull UIViewController *)controller didReturnSignature:(nonnull NSData *)signature {
    self.providerRegistrationTransaction.payloadSignature = signature;
    [self.model signTransactionInputs:self.providerRegistrationTransaction
                           completion:^(NSError *_Nonnull error){

                           }];
}


@end
