//
//  DWGenerateViewController.m
//  dashwallet
//
//  Created by Quantum Explorer on 10/11/17.
//  Copyright © 2018 Dash Core. All rights reserved.
//

#import "DWGenerateViewController.h"
#import "BREventManager.h"
#import "BRWalletManager.h"

@interface DWGenerateViewController ()

//@property (nonatomic, strong) IBOutlet UIView *wallpaper, *wallpaperContainer;
@property (nonatomic, strong) IBOutlet UIButton *generateButton, *showButton;
@property (nonatomic, strong) IBOutlet UILabel *startLabel, *recoverLabel;
@property (nonatomic, strong) UINavigationController *seedNav;

-(IBAction)generateRecoveryPhrase:(id)sender;
-(IBAction)show:(id)sender;

@end

@implementation DWGenerateViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.generateButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    self.generateButton.titleLabel.adjustsLetterSpacingToFitWidth = YES;
#pragma clang diagnostic pop
    
    //self.generateButton.superview.backgroundColor = [UIColor clearColor];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(BOOL)shouldPerformSegueWithIdentifier:(NSString *)identifier sender:(id)sender {
    if (! [BRWalletManager sharedInstance].passcodeEnabled) {
        [BREventManager saveEvent:@"welcome:passcode_disabled"];
        UIAlertController * alert = [UIAlertController
                                     alertControllerWithTitle:NSLocalizedString(@"turn device passcode on", nil)
                                     message:NSLocalizedString(@"\nA device passcode is needed to safeguard your wallet. Go to settings and turn "
                                                               "passcode on to continue.", nil)
                                     preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* okButton = [UIAlertAction
                                   actionWithTitle:NSLocalizedString(@"ok", nil)
                                   style:UIAlertActionStyleCancel
                                   handler:^(UIAlertAction * action) {
                                   }];
        [alert addAction:okButton];
        [self presentViewController:alert animated:YES completion:nil];
        return FALSE;
    }
    return TRUE;
}

-(void)performSegueWithIdentifier:(NSString *)identifier sender:(id)sender {
    [BREventManager saveEvent:@"welcome:generate"];
    
//    [self.navigationController.navigationBar.topItem setHidesBackButton:YES animated:YES];
//    [sender setEnabled:NO];
//    self.warningLabel.hidden = self.showButton.hidden = NO;
//    self.warningLabel.alpha = self.showButton.alpha = 0.0;
//    
//    [UIView animateWithDuration:0.5 animations:^{
//        self.warningLabel.alpha = self.showButton.alpha = 1.0;
//        self.navigationController.navigationBar.topItem.titleView.alpha = 0.33*0.5;
//        self.startLabel.alpha = self.recoverLabel.alpha = 0.33;
//        self.generateButton.alpha = 0.33;
//    }];
}

@end
