//
//  ZNWelcomeViewController.m
//  ZincWallet
//
//  Created by Aaron Voisine on 7/8/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNWelcomeViewController.h"

@interface ZNWelcomeViewController ()

@property (nonatomic, assign) CGPoint wallpaperStart, paralaxStart, walletStart, restoreStart;

@property (nonatomic, strong) IBOutlet UIImageView *wallpaper;
@property (nonatomic, strong) IBOutlet UIView *paralax;
@property (nonatomic, strong) IBOutlet UIButton *walletButton, *restoreButton;

@end

@implementation ZNWelcomeViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.navigationController.delegate = self;
}

- (void)viewDidUnload
{
    self.navigationController.delegate = nil;

    [super viewDidUnload];
}

- (void)viewWillAppear:(BOOL)animated
{
    static BOOL firstAppearance = YES;
    
    [super viewWillAppear:animated];
    
    if (firstAppearance) {
        firstAppearance = NO;
        
        self.wallpaperStart = self.wallpaper.center;
        self.paralaxStart = self.paralax.center;
        self.walletStart = self.walletButton.center;
        self.restoreStart = self.restoreButton.center;

        self.walletButton.center = CGPointMake(self.walletStart.x - self.view.frame.size.width, self.walletStart.y);
        self.restoreButton.center = CGPointMake(self.restoreStart.x - self.view.frame.size.width, self.restoreStart.y);
        self.paralax.center = CGPointMake(self.paralaxStart.x - self.view.frame.size.width/4, self.paralaxStart.y);
        
        [self.navigationController.view insertSubview:self.paralax atIndex:0];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    static BOOL firstAppearance = YES;

    [super viewDidAppear:animated];
    
    if (firstAppearance) {
        firstAppearance = NO;
        
        [UIView animateWithDuration:80.0 delay:0.0
        options:UIViewAnimationOptionCurveLinear|UIViewAnimationOptionRepeat|UIViewAnimationOptionAutoreverse
        animations:^{
            self.wallpaper.center = CGPointMake(self.wallpaperStart.x - 240, self.wallpaperStart.y - 45);
        } completion:nil];
        
        [UIView animateWithDuration:UINavigationControllerHideShowBarDuration*2 animations:^{
            self.walletButton.center = self.walletStart;
            self.restoreButton.center = self.restoreStart;
            self.paralax.center = self.paralaxStart;
        }];
    }
}

#pragma mark - UINavigationControllerDelegate

- (void)navigationController:(UINavigationController *)navigationController
didShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{
}

- (void)navigationController:(UINavigationController *)navigationController
willShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    if (! animated) return;

    [UIView animateWithDuration:UINavigationControllerHideShowBarDuration*2 animations:^{
        if (viewController != self) {
            self.paralax.center = CGPointMake(self.paralaxStart.x - self.view.frame.size.width/4, self.paralaxStart.y);
        }
        else self.paralax.center = self.paralaxStart;
    }];
}

@end
