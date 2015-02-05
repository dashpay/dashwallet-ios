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

#define LABEL_MARGIN       20.0
#define WRITE_TOGGLE_DELAY 15.0

@interface BRSeedViewController ()

//TODO: create a secure version of UILabel and use it for seedLabel, but make sure there's an accessibility work around
@property (nonatomic, strong) IBOutlet UILabel *seedLabel, *writeLabel;
@property (nonatomic, strong) IBOutlet UIButton *writeButton;
@property (nonatomic, strong) IBOutlet UIToolbar *toolbar;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *remindButton, *doneButton;
@property (nonatomic, strong) IBOutlet UIImageView *wallpaper;

@property (nonatomic, strong) NSString *seedPhrase;
@property (nonatomic, strong) id resignActiveObserver, screenshotObserver;

@end

@implementation BRSeedViewController

- (instancetype)customInit
{
    BRWalletManager *m = [BRWalletManager sharedInstance];

    if (m.noWallet) {
        self.seedPhrase = [m generateRandomSeed];
        [[BRPeerManager sharedInstance] connect];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:WALLET_NEEDS_BACKUP_KEY];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    else self.seedPhrase = m.seedPhrase; // this triggers authentication request

    if (self.seedPhrase.length > 0) _authSuccess = YES;

    return self;
}

- (instancetype)init
{
    if (! (self = [super init])) return nil;
    return [self customInit];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    if (! (self = [super initWithCoder:aDecoder])) return nil;
    return [self customInit];
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    if (! (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])) return nil;
    return [self customInit];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.wallpaper.hidden = (self.navigationController.viewControllers.firstObject != self) ? YES : NO;
    self.doneButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"done", nil)
                       style:UIBarButtonItemStylePlain target:self action:@selector(done:)];
    
    @autoreleasepool {  // @autoreleasepool ensures sensitive data will be dealocated immediately
        self.seedLabel.text = self.seedPhrase;
        self.seedPhrase = nil;
    }
    
#if DEBUG
    self.seedLabel.userInteractionEnabled = YES; // allow clipboard copy only for debug builds
#endif
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
 
    NSTimeInterval delay = WRITE_TOGGLE_DELAY;
 
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault animated:YES];
 
    // remove done button if we're not the root of the nav stack
    if (self.navigationController.viewControllers.firstObject != self) {
        self.toolbar.hidden = YES;
    }
    else delay *= 2; // extra delay before showing toggle when starting a new wallet
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:WALLET_NEEDS_BACKUP_KEY]) {
        [self performSelector:@selector(showWriteToggle) withObject:nil afterDelay:delay];
    }
    
    [UIView animateWithDuration:0.1 animations:^{
        self.seedLabel.alpha = 1.0;
    }];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    if (! self.resignActiveObserver) {
        self.resignActiveObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) {
                if (self.navigationController.viewControllers.firstObject != self) {
                    [self.navigationController popViewControllerAnimated:NO];
                }
            }];
    }
    
    //TODO: make it easy to create a new wallet and transfer balance
    if (! self.screenshotObserver) {
        self.screenshotObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationUserDidTakeScreenshotNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) {
                if ([[[BRWalletManager sharedInstance] wallet] balance] == 0) {
                    [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"WARNING", nil)
                      message:NSLocalizedString(@"Screenshots are visible to other apps and devices. "
                                                "Generate a new recovery phrase and keep it secret.", nil)
                      delegate:self cancelButtonTitle:nil otherButtonTitles:NSLocalizedString(@"new phrase", nil), nil]
                     show];
                }
                else {
                    [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"WARNING", nil)
                      message:NSLocalizedString(@"Screenshots are visible to other apps and devices. "
                                                "Your funds are at risk. Transfer your balance to another wallet.", nil)
                      delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
                }
            }];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];

    // don't leave the seed phrase laying around in memory any longer than necessary
    self.seedLabel.text = @"";
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    if (self.resignActiveObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.resignActiveObserver];
    self.resignActiveObserver = nil;
    if (self.screenshotObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.screenshotObserver];
    self.screenshotObserver = nil;
}

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    if (self.resignActiveObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.resignActiveObserver];
    if (self.screenshotObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.screenshotObserver];
}

- (void)showWriteToggle
{
    self.writeLabel.alpha = self.writeButton.alpha = 0.0;
    self.writeLabel.hidden = self.writeButton.hidden = NO;
    
    [UIView animateWithDuration:0.5 animations:^{
        self.writeLabel.alpha = self.writeButton.alpha = 1.0;
    }];
}

#pragma mark - IBAction

- (IBAction)done:(id)sender
{
    if (self.navigationController.viewControllers.firstObject != self) return;
    
    self.navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    [self.navigationController.presentingViewController.presentingViewController dismissViewControllerAnimated:YES
     completion:nil];
}

- (IBAction)refresh:(id)sender
{
    self.seedPhrase = [[BRWalletManager sharedInstance] generateRandomSeed];
    [[BRPeerManager sharedInstance] connect];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:WALLET_NEEDS_BACKUP_KEY];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    [UIView animateWithDuration:0.1 animations:^{
        self.seedLabel.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.seedLabel.text = self.seedPhrase;
        [UIView animateWithDuration:0.1 animations:^{ self.seedLabel.alpha = 1.0; }];
    }];
}

- (IBAction)toggleWrite:(id)sender
{
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];

    if ([defs boolForKey:WALLET_NEEDS_BACKUP_KEY]) {
        [self.toolbar setItems:@[self.toolbar.items[0], self.doneButton] animated:YES];
        [self.writeButton setImage:[UIImage imageNamed:@"checkbox-checked"] forState:UIControlStateNormal];
        [defs removeObjectForKey:WALLET_NEEDS_BACKUP_KEY];
    }
    else {
        [self.toolbar setItems:@[self.toolbar.items[0], self.remindButton] animated:YES];
        [self.writeButton setImage:[UIImage imageNamed:@"checkbox-empty"] forState:UIControlStateNormal];
        [defs setBool:YES forKey:WALLET_NEEDS_BACKUP_KEY];
    }
    
    [defs synchronize];
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) return;

    if ([[[BRWalletManager sharedInstance] wallet] balance] == 0 &&
        [[alertView buttonTitleAtIndex:buttonIndex] isEqual:NSLocalizedString(@"new phrase", nil)]) {
        [self refresh:nil];
    }
}

@end
