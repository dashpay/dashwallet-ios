//
//  DWGenerateViewController.m
//  dashwallet
//
//  Created by Quantum Explorer on 10/11/17.
//  Copyright © 2019 Dash Core. All rights reserved.
//

#import "DWGenerateViewController.h"
#import "DWWarningViewController.h"

@interface DWGenerateViewController ()

@property (nonatomic, strong) IBOutlet UIButton *generateButton, *showButton;
@property (nonatomic, strong) IBOutlet UILabel *startLabel, *recoverLabel;
@property (nonatomic, strong) UINavigationController *seedNav;

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

-(BOOL)prefersStatusBarHidden {
    return FALSE;
}


-(UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

-(BOOL)shouldPerformSegueWithIdentifier:(NSString *)identifier sender:(id)sender {
    if (![[DSAuthenticationManager sharedInstance] isPasscodeEnabled]) {
        [DSEventManager saveEvent:@"welcome:passcode_disabled"];
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

-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    [DSEventManager saveEvent:@"welcome:generate"];
}

@end
