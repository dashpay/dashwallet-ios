//
//  DWWarningViewController.m
//  DashWallet
//
//  Created by Sam Westrich on 8/3/18.
//  Copyright © 2019 Aaron Voisine. All rights reserved.
//

#import "DWWarningViewController.h"
#import <DashSync/DashSync.h>
#import "DWSeedViewController.h"

@interface DWWarningViewController ()

@property (strong, nonatomic) IBOutlet UILabel *eyeLabel;
@property (strong, nonatomic) IBOutlet UILabel *keyboardLabel;
@property (strong, nonatomic) IBOutlet UILabel *warningLabel;
@property (assign, nonatomic) DSBIP39Language desiredLanguage;

@end

@implementation DWWarningViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.warningLabel.text = NSLocalizedString(@"WARNING", nil);
    self.eyeLabel.text = NSLocalizedString(@"DO NOT let anyone see your recovery phrase or they can spend your dash.", nil);
    self.keyboardLabel.text = NSLocalizedString(@"NEVER type your recovery phrase into password managers or elsewhere. Other devices may be infected.",nil);
    self.desiredLanguage = DSBIP39Language_Default;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(IBAction)showChangeLanguageSelector:(id)sender {
    UIAlertController * changeLanguageSelector = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Choose Language", nil) message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray * languages = [DSBIP39Mnemonic availableLanguages];
    for (NSNumber * languageNumber in languages) {
        DSBIP39Language language = [languageNumber unsignedIntegerValue];
        NSString * languageCode = [DSBIP39Mnemonic identifierForLanguage:language];
        NSLocale *locale = [NSLocale currentLocale];
        
        NSString *languageString = [locale displayNameForKey:NSLocaleIdentifier
                                                 value:languageCode];
        UIAlertAction* languageAlertAction = [UIAlertAction
                                  actionWithTitle:languageString
                                  style:UIAlertActionStyleDefault
                                  handler:^(UIAlertAction * action) {
                                      self.desiredLanguage = language;
                                  }];
        [changeLanguageSelector addAction:languageAlertAction];
    }
    [self presentViewController:changeLanguageSelector animated:YES completion:nil];
    
}

-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    DWSeedViewController * seedViewController = segue.destinationViewController;
    seedViewController.inSetupMode = TRUE;
    seedViewController.desiredLanguage = self.desiredLanguage;
}

@end
