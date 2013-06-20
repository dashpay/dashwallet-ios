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

@property (nonatomic, strong) IBOutlet UILabel *seedLabel;
@property (nonatomic, strong) IBOutlet UIView *labelFrame;

@end

@implementation ZNSeedViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.labelFrame.layer.cornerRadius = 10.0;
    self.labelFrame.layer.shadowColor = [UIColor blackColor].CGColor;
    self.labelFrame.layer.shadowOffset = CGSizeMake(0.0, 2.0);
    self.labelFrame.layer.shadowOpacity = 0.25;
    self.labelFrame.layer.shadowRadius = 3.0;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
 
    // remove done button if we're not the root of the nav stack
    if (self.navigationController.viewControllers[0] != self) {
        self.navigationItem.leftBarButtonItem = nil;
        self.navigationItem.rightBarButtonItem = nil;
    }
    
    if (! [[ZNWallet sharedInstance] seed]) {
        [[ZNWallet sharedInstance] generateRandomSeed];
    }
    
    self.seedLabel.text = [[ZNWallet sharedInstance] seedPhrase];
    
    CGSize s = [self.seedLabel.text sizeWithFont:self.seedLabel.font
                constrainedToSize:CGSizeMake(self.seedLabel.frame.size.width, 140)];
    
    self.labelFrame.frame = CGRectMake(self.labelFrame.frame.origin.x, self.view.frame.size.height/2 - s.height/2 - 10,
                                       self.labelFrame.frame.size.width, s.height + 20);
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
                    constrainedToSize:CGSizeMake(self.seedLabel.frame.size.width, 140)];
        
        self.labelFrame.frame = CGRectMake(self.labelFrame.frame.origin.x,
                                           self.view.frame.size.height/2 - s.height/2 - 10,
                                           self.labelFrame.frame.size.width, s.height + 20);

        [UIView animateWithDuration:0.2 animations:^{ self.seedLabel.alpha = 1.0; }];
    }];

}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    [self.navigationController.presentingViewController.presentingViewController dismissViewControllerAnimated:YES
     completion:nil];
}

@end
