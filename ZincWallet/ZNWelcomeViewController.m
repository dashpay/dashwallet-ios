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
#define WALLPAPER_ANIMATION_Y 0.0

@interface ZNWelcomeViewController ()

@property (nonatomic, assign) CGPoint logoStart, walletStart, restoreStart, paralaxStart, wallpaperStart;
@property (nonatomic, assign) BOOL hasAppeared, animating;
@property (nonatomic, strong) id activeObserver, resignActiveObserver;

@property (nonatomic, strong) IBOutlet UIImageView *logo, *wallpaper;
@property (nonatomic, strong) IBOutlet UIView *paralax;
@property (nonatomic, strong) IBOutlet UIButton *walletButton, *restoreButton;

@end

@implementation ZNWelcomeViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    [self.navigationController.navigationBar
     setTitleTextAttributes:@{UITextAttributeTextColor:[UIColor whiteColor],
                              UITextAttributeTextShadowColor:[UIColor colorWithRed:0 green:0 blue:0 alpha:0.15],
                              UITextAttributeTextShadowOffset:[NSValue valueWithUIOffset:UIOffsetMake(0.0, 1.0)],
                              UITextAttributeFont:[UIFont fontWithName:@"HelveticaNeue" size:19.0]}];
    
    if ([self.navigationController.navigationBar respondsToSelector:@selector(shadowImage)]) {
        [self.navigationController.navigationBar setShadowImage:[UIImage new]];
    }
    
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
    
    self.resignActiveObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            self.wallpaper.center = self.wallpaperStart;
        }];
}

- (void)viewDidUnload
{
    self.navigationController.delegate = nil;

    [[NSNotificationCenter defaultCenter] removeObserver:self.activeObserver];
    [[NSNotificationCenter defaultCenter] removeObserver:self.resignActiveObserver];

    [super viewDidUnload];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (! self.hasAppeared) {
        self.wallpaperStart = self.wallpaper.center;
        self.logoStart = CGPointMake(self.logo.center.x - self.view.frame.size.width, self.logo.center.y);
        self.paralaxStart = self.paralax.center;
        self.walletStart = self.walletButton.center;
        self.restoreStart = self.restoreButton.center;

        self.walletButton.center = CGPointMake(self.walletStart.x + self.view.frame.size.width, self.walletStart.y);
        self.restoreButton.center = CGPointMake(self.restoreStart.x + self.view.frame.size.width, self.restoreStart.y);
        self.paralax.center = CGPointMake(self.paralaxStart.x + self.view.frame.size.width*PARALAX_RATIO,
                                          self.paralaxStart.y);
                
        [self.navigationController.view insertSubview:self.paralax atIndex:0];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if (! self.hasAppeared) {
        self.hasAppeared = YES;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:WALLPAPER_ANIMATION_DURATION delay:0.0
            options:UIViewAnimationOptionCurveLinear|UIViewAnimationOptionRepeat|UIViewAnimationOptionAutoreverse
            animations:^{
                self.animating = YES;
                self.wallpaper.center = CGPointMake(self.wallpaperStart.x - WALLPAPER_ANIMATION_X,
                                                self.wallpaperStart.y - WALLPAPER_ANIMATION_Y);
            } completion:^(BOOL finished) { self.animating = NO; }];
        
            [UIView animateWithDuration:UINavigationControllerHideShowBarDuration*2 delay:1.0 options:0 animations:^{
                self.walletButton.center = self.walletStart;
                self.restoreButton.center = self.restoreStart;
                self.logo.center = self.logoStart;
                self.paralax.center = self.paralaxStart;
            } completion:nil];
        });
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
