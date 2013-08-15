//
//  ZNRestoreViewController.m
//  ZincWallet
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

#import "ZNRestoreViewController.h"
#import "ZNWallet.h"
#import <QuartzCore/QuartzCore.h>

@interface ZNRestoreViewController ()

@property (nonatomic, strong) IBOutlet UITextView *textView;
@property (nonatomic, strong) IBOutlet UILabel *label;

@property (nonatomic, strong) NSSet *words;

@end

@implementation ZNRestoreViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.textView.layer.cornerRadius = 5.0;
    
    if (self.navigationController.viewControllers[0] == self) {
        self.textView.layer.borderColor = [[UIColor colorWithWhite:0.0 alpha:0.25] CGColor];
        self.textView.layer.borderWidth = 0.5;
        self.textView.textColor = [UIColor blackColor];

        if ([self.navigationController.navigationBar respondsToSelector:@selector(shadowImage)]) {
            [self.navigationController.navigationBar setShadowImage:[UIImage new]];
        }
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    //XXXX iOS 5 has a resizing bug, put in a fix here

    [self.textView becomeFirstResponder];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    self.words = [NSSet setWithArray:[NSArray arrayWithContentsOfFile:[[NSBundle mainBundle]
                  pathForResource:@"ElectrumSeedWords" ofType:@"plist"]]];
}

- (void)viewWillDisappear:(BOOL)animated
{
    self.words = nil;
    
    [super viewWillDisappear:animated];
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
    NSRange selected = textView.selectedRange;
    NSString *s = [textView.text lowercaseString];
    BOOL done = ([s rangeOfString:@"\n"].location != NSNotFound);


    if (! charset) {
        charset = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz "] invertedSet];
    }
    
    while ([s rangeOfCharacterFromSet:charset].location != NSNotFound) {
        NSRange r = [s rangeOfCharacterFromSet:charset];

        s = [[s substringToIndex:r.location] stringByAppendingString:[s substringFromIndex:r.location + 1]];
    }

    while ([s rangeOfString:@"  "].location != NSNotFound) {
        NSRange r = [s rangeOfString:@"  "];
        
        if (r.location + 1 == selected.location) selected.location++;
        s = [[s substringToIndex:r.location] stringByAppendingString:[s substringFromIndex:r.location + 1]];
    }
    
    if ([s hasPrefix:@" "]) s = [s substringFromIndex:1];

    selected.location -= textView.text.length - s.length;
    textView.text = s;
    textView.selectedRange = selected;
    
    if (done) {
        if ([s hasSuffix:@" "]) s = [s substringToIndex:s.length - 1];

        NSArray *a = [s componentsSeparatedByString:@" "];

        if (! [[NSSet setWithArray:a] isSubsetOfSet:self.words]) {
            NSUInteger i = [a indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
                return [self.words containsObject:obj] ? NO : (*stop = YES);
            }];
            
            textView.selectedRange = [textView.text rangeOfString:a[i]];
            
            [[[UIAlertView alloc] initWithTitle:nil
              message:[a[i] stringByAppendingString:@" is not a correct backup phrase word"] delegate:nil
              cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        }
        else if (a.count != 12) {
            [[[UIAlertView alloc] initWithTitle:nil message:@"backup phrase must be 12 words" delegate:nil
              cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        }
        else if ([[ZNWallet sharedInstance] seed]) {
            if ([[[ZNWallet sharedInstance] seedPhrase] isEqual:textView.text]) {
                [[[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:@"cancel"
                  destructiveButtonTitle:@"wipe" otherButtonTitles:nil]
                 showInView:[[UIApplication sharedApplication] keyWindow]];
            }
            else {
                [[[UIAlertView alloc] initWithTitle:nil message:@"backup phrase doesn't match" delegate:nil
                  cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
            }
        }
        else {
            [[ZNWallet sharedInstance] setSeedPhrase:textView.text];
        
            textView.text = nil;
                        
            [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
        }
    }
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == actionSheet.destructiveButtonIndex) {
        [[ZNWallet sharedInstance] setSeed:nil];

        self.textView.text = nil;

        UIViewController *p = self.navigationController.presentingViewController.presentingViewController;

        [p dismissViewControllerAnimated:NO completion:^{
            [p presentViewController:[self.storyboard instantiateViewControllerWithIdentifier:@"ZNNewWalletNav"]
             animated:NO completion:nil];
        }];
    }
}

@end
