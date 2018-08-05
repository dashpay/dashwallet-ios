//
//  DWWarningViewController.m
//  DashWallet
//
//  Created by Sam Westrich on 8/3/18.
//  Copyright © 2018 Aaron Voisine. All rights reserved.
//

#import "DWWarningViewController.h"
#import "BREventManager.h"
#import "BRWalletManager.h"

@interface DWWarningViewController ()

@property (strong, nonatomic) IBOutlet UILabel *eyeLabel;
@property (strong, nonatomic) IBOutlet UILabel *keyboardLabel;
@property (strong, nonatomic) IBOutlet UILabel *warningLabel;

@end

@implementation DWWarningViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.warningLabel.text = NSLocalizedString(@"WARNING", nil);
    self.eyeLabel.text = NSLocalizedString(@"DO NOT let anyone see your recovery\nphrase or they can spend your dash.", nil);
    self.keyboardLabel.text = NSLocalizedString(@"NEVER type your recovery phrase into\npassword managers or elsewhere.\nOther devices may be infected.",nil);
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)show:(id)sender
{
    [BREventManager saveEvent:@"welcome:show"];
}

@end
