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

//TODO: create a secure version of UILabel and use it for seedLabel
@property (nonatomic, strong) IBOutlet UILabel *seedLabel, *compatiblityLabel;
@property (nonatomic, strong) IBOutlet UIView *labelFrame;
@property (nonatomic, strong) IBOutlet UIImageView *wallpaper, *logo;
@property (nonatomic, strong) IBOutletCollection(UILabel) NSArray *otherLabels;

@property (nonatomic, strong) id resignActiveObserver;

@end

@implementation ZNSeedViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
#if DARK_THEME
    self.navigationItem.leftBarButtonItem.image = [UIImage imageNamed:@"refresh-white.png"];

    self.logo.image = [UIImage imageNamed:@"zincwallet-white.png"];
    self.logo.contentMode = UIViewContentModeCenter;
    self.logo.alpha = 0.9;
    
    [self.otherLabels enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        [obj setTextColor:[UIColor whiteColor]];
        [obj setShadowColor:[UIColor colorWithWhite:0.0 alpha:0.15]];
    }];
#else
    self.labelFrame.layer.borderColor = [[UIColor colorWithWhite:0.0 alpha:0.15] CGColor];
    self.labelFrame.layer.borderWidth = 1.0;
#endif
    self.labelFrame.layer.cornerRadius = 5.0;

    //self.labelFrame.layer.shadowRadius = 15.0;
    //self.labelFrame.layer.shadowOpacity = 0.1;
    //self.labelFrame.layer.shadowOffset = CGSizeMake(0.0, 1.0);
    //self.labelFrame.layer.masksToBounds = NO;
    
    if (self.navigationController.viewControllers[0] == self) {
        self.wallpaper.hidden = NO;
        
        if ([self.navigationController.navigationBar respondsToSelector:@selector(shadowImage)]) {
            [self.navigationController.navigationBar setShadowImage:[UIImage new]];
        }
    }
    else {
        self.wallpaper.hidden = YES;
    }
    
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
#if WALLET_BIP32
        self.compatiblityLabel.hidden = YES; // BIP32 isn't compatible with very much yet :(
#else
        self.compatiblityLabel.hidden = NO;
#endif
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
    self.navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    [self.navigationController.presentingViewController.presentingViewController dismissViewControllerAnimated:YES
     completion:nil];
}

@end
