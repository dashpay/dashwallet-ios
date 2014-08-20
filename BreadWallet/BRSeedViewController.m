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
#import "BRWallet.h"
#import "BRPeerManager.h"
#import "BRBIP32Sequence.h"

#define LABEL_MARGIN       20.0
#define WRITE_TOGGLE_DELAY 10.0

@interface BRSeedViewController ()

//TODO: create a secure version of UILabel and use it for seedLabel, but make sure there's an accessibility work around
@property (nonatomic, strong) IBOutlet UILabel *seedLabel, *writeLabel;
@property (nonatomic, strong) IBOutlet UISwitch *writeToggle;
@property (nonatomic, strong) IBOutlet UIToolbar *toolbar;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *remindButton, *doneButton;
@property (nonatomic, strong) IBOutlet UIImageView *wallpaper;

@property (nonatomic, strong) id resignActiveObserver, screenshotObserver;

@end

@implementation BRSeedViewController

- (instancetype)customInit
{
    if ([[UIApplication sharedApplication] isProtectedDataAvailable] && ! [[BRWalletManager sharedInstance] wallet]) {
        [[BRWalletManager sharedInstance] generateRandomSeed];
        [[BRPeerManager sharedInstance] connect];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:WALLET_NEEDS_BACKUP_KEY];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }

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
                       style:UIBarButtonItemStyleBordered target:self action:@selector(done:)];
    
    self.resignActiveObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            if (self.navigationController.viewControllers.firstObject != self) {
                [self.navigationController popViewControllerAnimated:NO];
            }
        }];


    //TODO: make it easy to create a new wallet and transfer balance
    self.screenshotObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationUserDidTakeScreenshotNotification
        object:nil queue:nil usingBlock:^(NSNotification *note) {
            if ([[[BRWalletManager sharedInstance] wallet] balance] == 0) {
                [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"WARNING", nil)
                  message:NSLocalizedString(@"Screenshots are visible to other apps and devices. "
                                            "Generate a new backup phrase and keep it secret.", nil)
                  delegate:self cancelButtonTitle:NSLocalizedString(@"ignore", nil)
                  otherButtonTitles:NSLocalizedString(@"new phrase", nil), nil] show];
            }
            else {
                [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"WARNING", nil)
                  message:NSLocalizedString(@"Screenshots are visible to other apps and devices. "
                                            "Your funds are at risk. Transfer your balance to another wallet.", nil)
                  delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
            }
        }];
}

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    if (self.resignActiveObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.resignActiveObserver];
    if (self.screenshotObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.screenshotObserver];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
 
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault animated:YES];
 
    // remove done button if we're not the root of the nav stack
    if (self.navigationController.viewControllers.firstObject != self) {
        self.toolbar.hidden = YES;
    }
    else [self performSelector:@selector(showWriteToggle) withObject:nil afterDelay:WRITE_TOGGLE_DELAY];
    
    @autoreleasepool {  // @autoreleasepool ensures sensitive data will be dealocated immediately
        self.seedLabel.text = [[BRWalletManager sharedInstance] seedPhrase];
    }
    
    [UIView animateWithDuration:0.1 animations:^{
        self.seedLabel.alpha = 1.0;
    }];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];

    // don't leave the seed phrase laying around in memory any longer than necessary
    self.seedLabel.text = @"";
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)showWriteToggle
{
    self.writeLabel.alpha = self.writeToggle.alpha = 0.0;
    self.writeLabel.hidden = self.writeToggle.hidden = NO;
    
    [UIView animateWithDuration:0.5 animations:^{
        self.writeLabel.alpha = self.writeToggle.alpha = 1.0;
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
    if (! [[UIApplication sharedApplication] isProtectedDataAvailable]) return;

    [[BRWalletManager sharedInstance] generateRandomSeed];
    [[BRPeerManager sharedInstance] connect];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:WALLET_NEEDS_BACKUP_KEY];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    [UIView animateWithDuration:0.1 animations:^{
        self.seedLabel.alpha = 0.0;
    } completion:^(BOOL finished) {
        @autoreleasepool {
            self.seedLabel.text = [[BRWalletManager sharedInstance] seedPhrase];
        }

        [UIView animateWithDuration:0.1 animations:^{
            self.seedLabel.alpha = 1.0;
        }];
    }];
}

- (IBAction)writeChanged:(id)sender
{
    if (self.writeToggle.on) {
        [self.toolbar setItems:@[self.toolbar.items[0], self.doneButton] animated:YES];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:WALLET_NEEDS_BACKUP_KEY];
    }
    else {
        [self.toolbar setItems:@[self.toolbar.items[0], self.remindButton] animated:YES];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:WALLET_NEEDS_BACKUP_KEY];
    }
    
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (IBAction)copy:(id)sender
{
    [[UIPasteboard generalPasteboard] setString:[[BRWalletManager sharedInstance] seedPhrase]];
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
