//
//  DWSeedViewController.m
//  DashWallet
//
//  Created by Aaron Voisine for BreadWallet on 6/12/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//  Copyright (c) 2018 Dash Core Group <contact@dash.org>
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

#import "DWSeedViewController.h"
#import "DWWhiteActionButton.h"
#import "DWVersionManager.h"

#define LABEL_MARGIN       20.0
#define WRITE_TOGGLE_DELAY 15.0

#define WALLET_NEEDS_BACKUP_KEY @"WALLET_NEEDS_BACKUP"

#define IDEO_SP   @"\xE3\x80\x80" // ideographic space (utf-8)


@interface DWSeedViewController ()

//OLDTODO: create a secure version of UILabel and use it for seedLabel, but make sure there's an accessibility work around
@property (nonatomic, strong) IBOutlet UILabel *seedLabel, *writeLabel;
@property (nonatomic, strong) IBOutlet UIButton *writeButton;
@property (strong, nonatomic) IBOutlet DWWhiteActionButton *doneButton;

@property (nonatomic, strong) id resignActiveObserver, screenshotObserver;

@end


@implementation DWSeedViewController

- (instancetype)customInit
{
    if (![DWEnvironment sharedInstance].currentWallet) {
        [DSWallet standardWalletWithRandomSeedPhraseForChain:[DWEnvironment sharedInstance].currentChain storeSeedPhrase:YES isTransient:NO];
        DSWallet * wallet = [DWEnvironment sharedInstance].currentWallet;
        self.seedPhrase = wallet.seedPhraseIfAuthenticated;
        [[DWEnvironment sharedInstance].currentChainManager.peerManager connect];
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
    if (!self.inSetupMode) {
        self.doneButton.hidden = YES;
    }
    else delay *= 2; // extra delay before showing toggle when starting a new wallet
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:WALLET_NEEDS_BACKUP_KEY]) {
        [self performSelector:@selector(showWriteToggle) withObject:nil afterDelay:delay];
    }
    
    [UIView animateWithDuration:0.1 animations:^{
        self.seedLabel.alpha = 1.0;
    }];
    
    
    @autoreleasepool {  // @autoreleasepool ensures sensitive data will be dealocated immediately
        NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        paragraphStyle.lineSpacing = 20;
        paragraphStyle.alignment = NSTextAlignmentCenter;
        NSInteger fontSize = 16;
        NSDictionary * attributes = nil;
        UIEdgeInsets edgeInsets = self.seedLabel.layoutMargins;
        if (self.seedPhrase.length > 0 && [self.seedPhrase characterAtIndex:0] > 0x1000) { // ideographic language
            NSInteger lineCount;
            NSMutableString *s,*l;
            do {
                lineCount = 1;
                CGRect r;
                s = CFBridgingRelease(CFStringCreateMutable(SecureAllocator(), 0));
                l = CFBridgingRelease(CFStringCreateMutable(SecureAllocator(), 0));
                for (NSString *w in CFBridgingRelease(CFStringCreateArrayBySeparatingStrings(SecureAllocator(),
                                                                                             (CFStringRef)self.seedPhrase, CFSTR(" ")))) {
                    if (l.length > 0) [l appendString:IDEO_SP];
                    [l appendString:w];
                    r = [l boundingRectWithSize:CGRectInfinite.size options:NSStringDrawingUsesLineFragmentOrigin
                                     attributes:@{NSFontAttributeName:[UIFont systemFontOfSize:fontSize weight:UIFontWeightMedium]} context:nil];
                    
                    if (r.size.width >= self.view.bounds.size.width - 54*2 - edgeInsets.left - edgeInsets.right) {
                        [s appendString:@"\n"];
                        l.string = w;
                        lineCount++;
                    }
                    else if (s.length > 0) [s appendString:IDEO_SP];
                    
                    [s appendString:w];
                }
                if (lineCount > 3) {
                    fontSize--;
                    if (fontSize < 5) break;
                    
                }
            } while (lineCount > 3);
            attributes = @{NSFontAttributeName:[UIFont systemFontOfSize:fontSize weight:UIFontWeightMedium],NSForegroundColorAttributeName:[UIColor whiteColor],NSParagraphStyleAttributeName:paragraphStyle};

            self.seedLabel.attributedText = [[NSAttributedString alloc] initWithString:s attributes:attributes];
        }
        else {
            NSInteger lineCount = 0;
            
            do {
                attributes = @{NSFontAttributeName:[UIFont systemFontOfSize:fontSize weight:UIFontWeightMedium],NSForegroundColorAttributeName:[UIColor whiteColor],NSParagraphStyleAttributeName:paragraphStyle};
                CGSize labelSize = (CGSize){self.view.frame.size.width - 54*2 - edgeInsets.left - edgeInsets.right, MAXFLOAT};
                CGRect requiredSize = [self.seedPhrase boundingRectWithSize:labelSize  options:NSStringDrawingUsesLineFragmentOrigin attributes:attributes context:nil];
                int charSize = lroundf(((UIFont*)attributes[NSFontAttributeName]).lineHeight + 12);
                int rHeight = lroundf(requiredSize.size.height);
                lineCount = rHeight/charSize;
                
                if (lineCount > 3) {
                    fontSize--;
                    if (fontSize < 5) break;
                    
                }
            } while (lineCount > 3);
            
            self.seedLabel.attributedText = [[NSAttributedString alloc] initWithString:self.seedPhrase attributes:attributes];
        }
        
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
                                                              if (!self.inSetupMode) {
                                                                  [self.navigationController popViewControllerAnimated:NO];
                                                              }
                                                          }];
    }
    
    //OLDTODO: make it easy to create a new wallet and transfer balance
    if (! self.screenshotObserver) {
        self.screenshotObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationUserDidTakeScreenshotNotification
                                                          object:nil queue:nil usingBlock:^(NSNotification *note) {
                                                              if (!self.inSetupMode) {
                                                                  
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
                                                                  [[DWEnvironment sharedInstance] clearAllWallets];
                                                                  UINavigationController * navigationController = (UINavigationController*)self.presentingViewController;
                                                                  [self dismissViewControllerAnimated:TRUE completion:nil];
                                                                  
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
                                                                  [navigationController.topViewController presentViewController:alert animated:YES completion:nil];
                                                                  
                                                                  
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

- (IBAction)toggleWrite:(id)sender
{
    [DSEventManager saveEvent:@"seed:toggle_write"];
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    
    if ([defs boolForKey:WALLET_NEEDS_BACKUP_KEY]) {
        [self.doneButton setTitle:NSLocalizedString(@"Done",nil) forState:UIControlStateNormal];
        [self.writeButton setImage:[UIImage imageNamed:@"checkbox-checked"] forState:UIControlStateNormal];
        [defs removeObjectForKey:WALLET_NEEDS_BACKUP_KEY];
    }
    else {
        [self.doneButton setTitle:NSLocalizedString(@"Remind me later",nil) forState:UIControlStateNormal];
        [self.writeButton setImage:[UIImage imageNamed:@"checkbox-empty"] forState:UIControlStateNormal];
        [defs setBool:YES forKey:WALLET_NEEDS_BACKUP_KEY];
    }
    
    [defs synchronize];
}



@end
