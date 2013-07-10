//
//  ZNWelcomeViewController.m
//  ZincWallet
//
//  Created by Aaron Voisine on 7/8/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNWelcomeViewController.h"

#define WALLPAPER_ANIMATION_DURATION 60.0
#define WALLPAPER_ANIMATION_X 240.0
#define WALLPAPER_ANIMATION_Y 45.0
#define PARALAX_RATIO 0.25

@interface ZNWelcomeViewController ()

@property (nonatomic, assign) CGPoint wallpaperStart, paralaxStart, walletStart, restoreStart;
@property (nonatomic, assign) BOOL hasAppeared, animating;
@property (nonatomic, strong) id activeObserver;

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
    
    self.activeObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            if (self.animating) return;
            
            self.wallpaper.center = self.wallpaperStart;
            
            [UIView animateWithDuration:WALLPAPER_ANIMATION_DURATION delay:0.0
            options:UIViewAnimationOptionCurveLinear|UIViewAnimationOptionRepeat|UIViewAnimationOptionAutoreverse
            animations:^{
                self.animating = YES;
                self.wallpaper.center = CGPointMake(self.wallpaperStart.x - WALLPAPER_ANIMATION_X,
                                                    self.wallpaperStart.y - WALLPAPER_ANIMATION_Y);
            } completion:^(BOOL finished) { self.animating = NO; }];
        }];
}

- (void)viewDidUnload
{
    self.navigationController.delegate = nil;

    [[NSNotificationCenter defaultCenter] removeObserver:self.activeObserver];

    [super viewDidUnload];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (! self.hasAppeared) {
        self.wallpaperStart = self.wallpaper.center;
        self.paralaxStart = self.paralax.center;
        self.walletStart = self.walletButton.center;
        self.restoreStart = self.restoreButton.center;

        self.walletButton.center = CGPointMake(self.walletStart.x - self.view.frame.size.width, self.walletStart.y);
        self.restoreButton.center = CGPointMake(self.restoreStart.x - self.view.frame.size.width, self.restoreStart.y);
        self.paralax.center = CGPointMake(self.paralaxStart.x - self.view.frame.size.width*PARALAX_RATIO,
                                          self.paralaxStart.y);
        
        [self.navigationController.view insertSubview:self.paralax atIndex:0];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if (! self.hasAppeared) {
        self.hasAppeared = YES;
        
        [UIView animateWithDuration:WALLPAPER_ANIMATION_DURATION delay:0.0
        options:UIViewAnimationOptionCurveLinear|UIViewAnimationOptionRepeat|UIViewAnimationOptionAutoreverse
        animations:^{
            self.animating = YES;
            self.wallpaper.center = CGPointMake(self.wallpaperStart.x - WALLPAPER_ANIMATION_X,
                                                self.wallpaperStart.y - WALLPAPER_ANIMATION_Y);
        } completion:^(BOOL finished) { self.animating = NO; }];
        
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
            self.paralax.center = CGPointMake(self.paralaxStart.x - self.view.frame.size.width*PARALAX_RATIO,
                                              self.paralaxStart.y);
        }
        else self.paralax.center = self.paralaxStart;
    }];
}

@end
