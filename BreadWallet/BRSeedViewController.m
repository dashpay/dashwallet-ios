//
//  BRSeedViewController.m
//  BreadWallet
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

#import "BRSeedViewController.h"
#import "BRWalletManager.h"
#import "BRPeerManager.h"
#import "BRBIP32Sequence.h"

#define LABEL_MARGIN 20

@interface BRSeedViewController ()

//TODO: create a secure version of UILabel and use it for seedLabel, but make sure there's an accessibility work around
@property (nonatomic, strong) IBOutlet UILabel *seedLabel, *warningLabel;
@property (nonatomic, strong) IBOutlet UIView *labelFrame;
@property (nonatomic, strong) IBOutlet UIImageView *wallpaper, *logo;

@property (nonatomic, strong) id resignActiveObserver;

@end

@implementation BRSeedViewController

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
    BRWalletManager *m = [BRWalletManager sharedInstance];

    [super viewWillAppear:animated];
 
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault animated:YES];
 
    // remove done button if we're not the root of the nav stack
    if (self.navigationController.viewControllers.firstObject != self) {
        self.navigationItem.leftBarButtonItem = nil;
    }

    if (! m.wallet && [[UIApplication sharedApplication] isProtectedDataAvailable]) {
        [m generateRandomSeed];
        [[BRPeerManager sharedInstance] connect];
    }
    else self.navigationItem.rightBarButtonItem = nil;

    [UIView animateWithDuration:0.1 animations:^{
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

//    [[[UIAlertView alloc] initWithTitle:nil message:@"you can see your backup phrase again under settings" delegate:self
//      cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
//    self.navigationController.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self.navigationController.presentingViewController.presentingViewController dismissViewControllerAnimated:YES
     completion:nil];
}

- (IBAction)refresh:(id)sender
{
    if (! [[UIApplication sharedApplication] isProtectedDataAvailable]) return;

    [[BRWalletManager sharedInstance] generateRandomSeed];
    
    [UIView animateWithDuration:0.1 animations:^{
        self.seedLabel.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.seedLabel.text = [[BRWalletManager sharedInstance] seedPhrase];
        
        [UIView animateWithDuration:0.1 animations:^{
            self.seedLabel.alpha = 1.0;
        }];
    }];
}

- (IBAction)copy:(id)sender
{
    [[UIPasteboard generalPasteboard] setString:[[BRWalletManager sharedInstance] seedPhrase]];
}

//#pragma mark - UIAlertViewDelegate
//
//- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
//{
//    self.navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
//    [self.navigationController.presentingViewController.presentingViewController dismissViewControllerAnimated:YES
//     completion:nil];
//}

@end
