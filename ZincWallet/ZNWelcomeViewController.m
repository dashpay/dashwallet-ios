//
//  ZNWelcomeViewController.m
//  ZincWallet
//
//  Created by Aaron Voisine on 7/8/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNWelcomeViewController.h"

@interface ZNWelcomeViewController ()

@property (nonatomic, assign) CGPoint wallpaperStart, walletStart, restoreStart;

@property (nonatomic, strong) IBOutlet UIImageView *wallpaper;
@property (nonatomic, strong) IBOutlet UIButton *walletButton, *restoreButton;

@end

@implementation ZNWelcomeViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.    
}

- (void)viewWillAppear:(BOOL)animated
{
    static BOOL firstAppearance = YES;
    
    [super viewWillAppear:animated];
    
    if (firstAppearance) {
        firstAppearance = NO;
        
        self.wallpaperStart = self.wallpaper.center;
        self.walletStart = self.walletButton.center;
        self.restoreStart = self.restoreButton.center;

        //self.wallpaper.center = CGPointMake(self.wallpaperStart.x - 45, self.wallpaperStart.y);
        self.walletButton.center = CGPointMake(self.walletStart.x - 260, self.walletStart.y);
        self.restoreButton.center = CGPointMake(self.restoreStart.x - 260, self.restoreStart.y);
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    static BOOL firstAppearance = YES;

    [super viewDidAppear:animated];
    
    if (firstAppearance) {
        firstAppearance = NO;
        
        [self.navigationController.view insertSubview:self.wallpaper atIndex:0];
        
        [UIView animateWithDuration:60.0 delay:0.0
        options:UIViewAnimationOptionCurveLinear|UIViewAnimationOptionRepeat|UIViewAnimationOptionAutoreverse
        animations:^{
            self.wallpaper.center = CGPointMake(self.wallpaperStart.x - 180, self.wallpaperStart.y - 45);
        } completion:nil];
        
        [UIView animateWithDuration:0.25 animations:^{
            self.walletButton.center = self.walletStart;
            self.restoreButton.center = self.restoreStart;
        }];
    }
}

@end
