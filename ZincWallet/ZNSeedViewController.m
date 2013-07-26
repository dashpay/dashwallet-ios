//
//  ZNSeedViewController.m
//  ZincWallet
//
//  Created by Aaron Voisine on 6/12/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNSeedViewController.h"
#import "ZNWallet.h"
#import <QuartzCore/QuartzCore.h>

@interface ZNSeedViewController ()

@property (nonatomic, strong) IBOutlet UILabel *seedLabel, *compatiblityLabel;
@property (nonatomic, strong) IBOutlet UIView *labelFrame;

@property (nonatomic, strong) id resignActiveObserver;

@end

@implementation ZNSeedViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.labelFrame.layer.cornerRadius = 5.0;
    self.labelFrame.layer.borderWidth = 0.5;
    self.labelFrame.layer.borderColor = [[UIColor colorWithWhite:0.85 alpha:1.0] CGColor];
    
    self.resignActiveObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            if (self.navigationController.viewControllers[0] != self) {
                [self.navigationController popViewControllerAnimated:NO];
            }
        }];
}

- (void)viewWillUnload
{
    [[NSNotificationCenter defaultCenter] removeObserver:self.resignActiveObserver];

    [super viewWillUnload];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
 
    // remove done button if we're not the root of the nav stack
    if (self.navigationController.viewControllers[0] != self) {
        self.navigationItem.leftBarButtonItem = nil;
    }

    if (! [[ZNWallet sharedInstance] seed]) {
        [[ZNWallet sharedInstance] generateRandomSeed];
        self.compatiblityLabel.hidden = YES;
    }
    else {
        self.navigationItem.rightBarButtonItem = nil;
    }

    self.seedLabel.text = [[ZNWallet sharedInstance] seedPhrase];
    
    CGSize s = [self.seedLabel.text sizeWithFont:self.seedLabel.font
                constrainedToSize:CGSizeMake(self.seedLabel.frame.size.width, CGFLOAT_MAX)];
    
    self.labelFrame.frame = CGRectMake(self.labelFrame.frame.origin.x, self.view.frame.size.height/2 - s.height/2 - 11,
                                       self.labelFrame.frame.size.width, s.height + 22);
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
    [[[UIAlertView alloc] initWithTitle:nil message:@"You can see your backup phrase again under settings" delegate:self
      cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}

- (IBAction)refresh:(id)sender
{
    [[ZNWallet sharedInstance] generateRandomSeed];
    
    [UIView animateWithDuration:0.2 animations:^{ self.seedLabel.alpha = 0.0; }
     completion:^(BOOL finished) {
        self.seedLabel.text = [[ZNWallet sharedInstance] seedPhrase];
        
        CGSize s = [self.seedLabel.text sizeWithFont:self.seedLabel.font
                    constrainedToSize:CGSizeMake(self.seedLabel.frame.size.width, CGFLOAT_MAX)];
        
        self.labelFrame.frame = CGRectMake(self.labelFrame.frame.origin.x,
                                           self.view.frame.size.height/2 - s.height/2 - 11,
                                           self.labelFrame.frame.size.width, s.height + 22);

        [UIView animateWithDuration:0.2 animations:^{ self.seedLabel.alpha = 1.0; }];
    }];

}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    self.navigationController.modalTransitionStyle = UIModalTransitionStyleFlipHorizontal;
    [self.navigationController.presentingViewController.presentingViewController dismissViewControllerAnimated:YES
     completion:nil];
}

@end
