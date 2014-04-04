//
//  ZNSeedViewController.m
//  ZincWallet
//
//  Created by Aaron Voisine on 6/12/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "ZNSeedViewController.h"
#import "ZNWalletManager.h"
#import "ZNPeerManager.h"
#import "ZNBIP32Sequence.h"

#define LABEL_MARGIN 20

@interface ZNSeedViewController ()

//TODO: create a secure version of UILabel and use it for seedLabel, but make sure there's an accessibility work around
@property (nonatomic, strong) IBOutlet UILabel *seedLabel, *warningLabel, *compatiblityLabel, *exportLabel;
@property (nonatomic, strong) IBOutlet UIView *labelFrame;
@property (nonatomic, strong) IBOutlet UIImageView *wallpaper, *logo;

@property (nonatomic, strong) id resignActiveObserver;

@end

@implementation ZNSeedViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.wallpaper.hidden = (self.navigationController.viewControllers.firstObject != self) ? YES : NO;
    
    self.resignActiveObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            if (self.navigationController.viewControllers.firstObject != self) {
                [self.navigationController popViewControllerAnimated:NO];
            }
        }];
}

- (void)dealloc
{
    if (self.resignActiveObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.resignActiveObserver];
}

- (void)viewWillAppear:(BOOL)animated
{
    ZNWalletManager *m = [ZNWalletManager sharedInstance];

    [super viewWillAppear:animated];
 
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault animated:YES];
 
    // remove done button if we're not the root of the nav stack
    if (self.navigationController.viewControllers.firstObject != self) {
        self.navigationItem.leftBarButtonItem = nil;
    }

    if (! m.wallet) {
        [m generateRandomSeed];
        [[ZNPeerManager sharedInstance] connect];
        self.compatiblityLabel.hidden = YES;
    }
    else {
        self.navigationItem.rightBarButtonItem = nil;
        self.compatiblityLabel.hidden = YES; // BIP32 isn't compatible with very much yet :(
        self.exportLabel.text =
            [@"BIP32 extended private key: "
             stringByAppendingString:[[ZNBIP32Sequence new] serializedPrivateMasterFromSeed:m.seed]];
    }

    [UIView animateWithDuration:SEGUE_DURATION/2 animations:^{
        self.seedLabel.alpha = 1.0;
    }];
    
    self.seedLabel.text = m.seedPhrase;
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];

    // don't leave the seed phrase laying around in memory any longer than necessary
    self.seedLabel.text = @"";
}

#pragma mark - IBAction

- (IBAction)done:(id)sender
{
    if (self.navigationController.viewControllers.firstObject != self) return;

    [[[UIAlertView alloc] initWithTitle:nil message:@"you can see your backup phrase again under settings" delegate:self
      cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
}

- (IBAction)refresh:(id)sender
{
    [[ZNWalletManager sharedInstance] generateRandomSeed];
    
    [UIView animateWithDuration:SEGUE_DURATION/2 animations:^{
        self.seedLabel.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.seedLabel.text = [[ZNWalletManager sharedInstance] seedPhrase];
        
        [UIView animateWithDuration:SEGUE_DURATION/2 animations:^{
            self.seedLabel.alpha = 1.0;
        }];
    }];
}

- (IBAction)copy:(id)sender
{
    [[UIPasteboard generalPasteboard] setString:[[ZNWalletManager sharedInstance] seedPhrase]];
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    self.navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    [self.navigationController.presentingViewController.presentingViewController dismissViewControllerAnimated:YES
     completion:nil];
}

@end
