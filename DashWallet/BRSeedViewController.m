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

#import <DashSync/DashSync.h>

#import "BRSeedViewController.h"

#define LABEL_MARGIN       20.0
#define WRITE_TOGGLE_DELAY 15.0

#define IDEO_SP   @"\xE3\x80\x80" // ideographic space (utf-8)


@interface BRSeedViewController ()

//TODO: create a secure version of UILabel and use it for seedLabel, but make sure there's an accessibility work around
@property (nonatomic, strong) IBOutlet UILabel *seedLabel, *writeLabel;
@property (nonatomic, strong) IBOutlet UIButton *writeButton;
@property (nonatomic, strong) IBOutlet UIToolbar *toolbar;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *remindButton, *doneButton;
@property (nonatomic, strong) IBOutlet UIImageView *wallpaper;

@property (nonatomic, strong) id resignActiveObserver, screenshotObserver;

@end


@implementation BRSeedViewController

- (instancetype)customInit
{
    DSWalletManager *manager = [DSWalletManager sharedInstance];

    if (manager.noWallet) {
        self.seedPhrase = [manager generateRandomSeed];
        [[DSChainManager sharedInstance] connect];
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
    
    if (self.navigationController.viewControllers.firstObject != self) {
        self.wallpaper.hidden = YES;
        self.view.backgroundColor = [UIColor clearColor];
    }
    
    self.doneButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"done", nil)
                       style:UIBarButtonItemStylePlain target:self action:@selector(done:)];
    
    
#if DEBUG
    self.seedLabel.userInteractionEnabled = YES; // allow clipboard copy only for debug builds
#endif
}

-(UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
 
    NSTimeInterval delay = WRITE_TOGGLE_DELAY;
 
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
    
    
    @autoreleasepool {  // @autoreleasepool ensures sensitive data will be dealocated immediately
        if (self.seedPhrase.length > 0 && [self.seedPhrase characterAtIndex:0] > 0x3000) { // ideographic language
            CGRect r;
            NSMutableString *s = CFBridgingRelease(CFStringCreateMutable(SecureAllocator(), 0)),
            *l = CFBridgingRelease(CFStringCreateMutable(SecureAllocator(), 0));
            
            for (NSString *w in CFBridgingRelease(CFStringCreateArrayBySeparatingStrings(SecureAllocator(),
                                                                                         (CFStringRef)self.seedPhrase, CFSTR(" ")))) {
                if (l.length > 0) [l appendString:IDEO_SP];
                [l appendString:w];
                r = [l boundingRectWithSize:CGRectInfinite.size options:NSStringDrawingUsesLineFragmentOrigin
                                 attributes:@{NSFontAttributeName:self.seedLabel.font} context:nil];
                
                if (r.size.width + LABEL_MARGIN*2.0 >= self.view.bounds.size.width) {
                    [s appendString:@"\n"];
                    l.string = w;
                }
                else if (s.length > 0) [s appendString:IDEO_SP];
                
                [s appendString:w];
            }
            
            self.seedLabel.text = s;
        }
        else self.seedLabel.text = self.seedPhrase;
        
        self.seedPhrase = nil;
    }
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
                if (self.navigationController.viewControllers.firstObject != self) {
                    
                    UIAlertController * alert = [UIAlertController
                                                 alertControllerWithTitle:NSLocalizedString(@"WARNING", nil)
                                                 message:NSLocalizedString(@"Screenshots are visible to other apps and devices. "
                                                                           "Your funds are at risk. Transfer your balance to another wallet.", nil)
                                                 preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction* okButton = [UIAlertAction
                                               actionWithTitle:NSLocalizedString(@"ok", nil)
                                               style:UIAlertActionStyleCancel
                                               handler:^(UIAlertAction * action) {
                                               }];
                    [alert addAction:okButton];
                    [self presentViewController:alert animated:YES completion:nil];
                }
                else {
                    [[DSWalletManager sharedInstance] setSeedPhrase:nil];
                    [self.navigationController.presentingViewController dismissViewControllerAnimated:NO
                     completion:nil];
                    
                    UIAlertController * alert = [UIAlertController
                                                 alertControllerWithTitle:NSLocalizedString(@"WARNING", nil)
                                                 message:NSLocalizedString(@"Screenshots are visible to other apps and devices. "
                                                                           "Generate a new recovery phrase and keep it secret.", nil)
                                                 preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction* okButton = [UIAlertAction
                                               actionWithTitle:NSLocalizedString(@"ok", nil)
                                               style:UIAlertActionStyleCancel
                                               handler:^(UIAlertAction * action) {
                                               }];
                    [alert addAction:okButton];
                    [self presentViewController:alert animated:YES completion:nil];
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

// MARK: - IBAction

- (IBAction)done:(id)sender
{
    [DSEventManager saveEvent:@"seed:dismiss"];
    if (self.navigationController.viewControllers.firstObject != self) return;
    
    self.navigationController.presentingViewController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    [self.navigationController.presentingViewController.presentingViewController dismissViewControllerAnimated:YES
     completion:nil];
}

- (IBAction)toggleWrite:(id)sender
{
    [DSEventManager saveEvent:@"seed:toggle_write"];
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

@end
