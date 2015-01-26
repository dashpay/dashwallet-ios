//
//  BRRestoreViewController.m
//  BreadWallet
//
//  Created by Aaron Voisine on 6/13/13.
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

#import "BRRestoreViewController.h"
#import "BRWalletManager.h"
#import "BRKeySequence.h"
#import "BRBIP39Mnemonic.h"
#import "NSString+Base58.h"

#define PHRASE_LENGTH 12
#define WORDS         @"BIP39EnglishWords"

@interface BRRestoreViewController ()

@property (nonatomic, strong) IBOutlet UITextView *textView;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *textViewYBottom;
@property (nonatomic, strong) NSArray *words;
@property (nonatomic, strong) id keyboardObserver;

@end

@implementation BRRestoreViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.

     self.words = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:WORDS ofType:@"plist"]];
     
    // TODO: create secure versions of keyboard and UILabel and use in place of UITextView
    // TODO: autocomplete based on 4 letter prefixes of mnemonic words
    
    self.textView.layer.cornerRadius = 5.0;
    
    self.keyboardObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIKeyboardWillShowNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            [UIView animateWithDuration:[note.userInfo[UIKeyboardAnimationDurationUserInfoKey] floatValue] delay:0.0
             options:[note.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue] animations:^{
                 self.textViewYBottom.constant =
                     [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue].size.height + 12.0;
                 [self.view layoutIfNeeded];
             } completion:nil];
        }];
    
    if (self.navigationController.viewControllers.firstObject != self) return;
    
    self.textView.layer.borderColor = [[UIColor colorWithWhite:0.0 alpha:0.25] CGColor];
    self.textView.layer.borderWidth = 0.5;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self.textView becomeFirstResponder];
}

- (void)dealloc
{
    if (self.keyboardObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.keyboardObserver];
}

- (void)wipeWithPhrase:(NSString *)phrase
{
    @autoreleasepool {
        NSString *seedPhrase = [[BRWalletManager sharedInstance] seedPhrase];
        
        if (seedPhrase && ([phrase isEqual:seedPhrase] || [phrase isEqual:@"wipe"])) {
            [[[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:NSLocalizedString(@"cancel", nil)
              destructiveButtonTitle:NSLocalizedString(@"wipe", nil) otherButtonTitles:nil]
             showInView:[[UIApplication sharedApplication] keyWindow]];
        }
        else if (seedPhrase) {
            [[[UIAlertView alloc] initWithTitle:nil message:NSLocalizedString(@"recovery phrase doesn't match", nil)
              delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        }
        else [self.textView becomeFirstResponder];
    }
}

#pragma mark - IBAction

- (IBAction)cancel:(id)sender
{
    [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView
{
    static NSCharacterSet *charset = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        NSMutableCharacterSet *set = [NSMutableCharacterSet letterCharacterSet];

        [set addCharactersInString:@"., "];
        charset = [set invertedSet];
    });

    @autoreleasepool {  // @autoreleasepool ensures sensitive data will be dealocated immediately
        BRWalletManager *m = [BRWalletManager sharedInstance];
        NSRange selected = textView.selectedRange;
        NSMutableString *s = CFBridgingRelease(CFStringCreateMutableCopy(SecureAllocator(), 0,
                                                                         (CFStringRef)textView.text));
        BOOL done = ([s rangeOfString:@"\n"].location != NSNotFound);
    
        while ([s rangeOfCharacterFromSet:charset].location != NSNotFound) {
            [s deleteCharactersInRange:[s rangeOfCharacterFromSet:charset]];
        }

        while ([s rangeOfString:@"  "].location != NSNotFound) {
            NSRange r = [s rangeOfString:@".  "];
    
            if (r.location != NSNotFound) {
                if (r.location + 2 == selected.location) selected.location++;
                [s deleteCharactersInRange:NSMakeRange(r.location + 1, 1)];
            }
            else [s replaceOccurrencesOfString:@"  " withString:@". " options:0 range:NSMakeRange(0, s.length)];
        }
    
        if ([s hasPrefix:@" "]) [s deleteCharactersInRange:NSMakeRange(0, 1)];

        selected.location -= textView.text.length - s.length;
        textView.text = s;
        textView.selectedRange = selected;
    
        if (! done) return;

        NSString *phrase = [[BRBIP39Mnemonic sharedInstance] normalizePhrase:s], *incorrect = nil;
        NSArray *a = CFBridgingRelease(CFStringCreateArrayBySeparatingStrings(SecureAllocator(), (CFStringRef)phrase,
                                                                              CFSTR(" ")));

        for (NSString *word in a) {
            if ([self.words containsObject:word]) continue;
            incorrect = word;
            break;
        }

        if ([s isEqual:@"wipe"]) { // shortcut word to force the wipe option to appear
            [self.textView resignFirstResponder];
            [self performSelector:@selector(wipeWithPhrase:) withObject:s afterDelay:0.0];
        }
        else if (incorrect) {
            textView.selectedRange = [[textView.text lowercaseString] rangeOfString:incorrect];
        
            [[[UIAlertView alloc] initWithTitle:nil
              message:[NSString stringWithFormat:NSLocalizedString(@"\"%@\" is not a recovery phrase word", nil),
                       incorrect] delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil]
             show];
        }
        else if (a.count != PHRASE_LENGTH) {
            [[[UIAlertView alloc] initWithTitle:nil
              message:[NSString stringWithFormat:NSLocalizedString(@"recovery phrase must have %d words", nil),
                       PHRASE_LENGTH] delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil)
              otherButtonTitles:nil] show];
        }
        else if (! [[BRBIP39Mnemonic sharedInstance] phraseIsValid:phrase]) {
            [[[UIAlertView alloc] initWithTitle:nil message:NSLocalizedString(@"bad recovery phrase", nil) delegate:nil
              cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        }
        else if (m.wallet) {
            [self.textView resignFirstResponder];
            [self performSelector:@selector(wipeWithPhrase:) withObject:s afterDelay:0.0];
        }
        else {
            //TODO: offer the user an option to move funds to a new seed if their wallet device was lost or stolen
            m.seedPhrase = textView.text;
            textView.text = nil;
            
            [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:^{
                [m performSelector:@selector(setPin) withObject:nil afterDelay:0.3];
            }];
        }
    }
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex != actionSheet.destructiveButtonIndex) {
        [self.textView becomeFirstResponder];
        return;
    }
    
    [[BRWalletManager sharedInstance] setSeedPhrase:nil];
    self.textView.text = nil;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:WALLET_NEEDS_BACKUP_KEY];
    [[NSUserDefaults standardUserDefaults] synchronize];

    UIViewController *p = self.navigationController.presentingViewController.presentingViewController;
    
    [p dismissViewControllerAnimated:NO completion:^{
        [p presentViewController:[self.storyboard instantiateViewControllerWithIdentifier:@"NewWalletNav"] animated:NO
         completion:nil];
    }];
}

@end
