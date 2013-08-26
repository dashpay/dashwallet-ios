//
//  ZNAppDelegate.m
//  ZincWallet
//
//  Created by Aaron Voisine on 5/8/13.
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

#import "ZNAppDelegate.h"
#import "NSString+Base58.h"
#import "NSManagedObjectContext+Utils.h"
#import <MessageUI/MessageUI.h>

@implementation ZNAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Override point for customization after application launch.

    [self keepUpAppearances];

    //TODO: digitally sign every source release
    
    //TODO: need to upgrade openssl (and other libs) to latest
    
    //TODO: need to implement pin code

    //TODO: need to have a network status indicator perferrably tied to websocket status
    
    //TODO: figure what to do about bluetooth
    // this will notify user if bluetooth is disabled (on 4S and newer devices that support BTLE)
    //CBCentralManager *cbManager = [[CBCentralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue()];
    
    //[self centralManagerDidUpdateState:cbManager]; // Show initial state
    
    return YES;
}
							
- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of
    // temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application
    // and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use
    // this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application
    // state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate:
    // when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes
    // made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application
    // was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Saves changes in the application's managed object context before the application terminates.
    [[NSManagedObjectContext sharedInstance] saveContext];
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication
annotation:(id)annotation
{
    if (! url.host && url.resourceSpecifier) {
        url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@", url.scheme, url.resourceSpecifier]];
    }

    if (! [url.scheme isEqual:@"bitcoin"] || ! [url.host isValidBitcoinAddress]) return NO;

    [[NSNotificationCenter defaultCenter] postNotificationName:bitcoinURLNotification object:self
     userInfo:@{@"url":url}];
    
    return YES;
}

#pragma mark - appearance

- (void)keepUpAppearances
{
    const float mask[6] = { 222, 255, 222, 255, 222, 255 };

    [[UINavigationBar appearance]
     setBackgroundImage:[UIImage imageWithCGImage:CGImageCreateWithMaskingColors([[UIImage new] CGImage], mask)]
     forBarMetrics:UIBarMetricsDefault];

    [[UINavigationBar appearance]
     setTitleTextAttributes:@{UITextAttributeTextColor:[UIColor grayColor],
                              UITextAttributeTextShadowColor:[UIColor whiteColor],
                              UITextAttributeTextShadowOffset:[NSValue valueWithUIOffset:UIOffsetMake(0.0, 1.0)],
                              UITextAttributeFont:[UIFont fontWithName:@"HelveticaNeue" size:19.0]}];

    // this is broken in iOS 6
    if ([[UINavigationBar appearance] respondsToSelector:@selector(shadowImage)]) {
        [[UINavigationBar appearance] setShadowImage:[UIImage new]];
    }

    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackOpaque];
    
    [[UIBarButtonItem appearanceWhenContainedIn:[UINavigationBar class], nil]
     setTitleTextAttributes:@{UITextAttributeTextColor:[UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:1.0],
                              UITextAttributeTextShadowColor:[UIColor whiteColor],
                              UITextAttributeTextShadowOffset:[NSValue valueWithUIOffset:UIOffsetMake(0.0, 0.0)],
                              UITextAttributeFont:[UIFont fontWithName:@"HelveticaNeue-Light" size:17.0]}
     forState:UIControlStateNormal];
    
    [[UIBarButtonItem appearanceWhenContainedIn:[UINavigationBar class], nil]
     setTitleTextAttributes:@{UITextAttributeTextColor:[UIColor colorWithRed:0.0 green:0.25 blue:0.5 alpha:1.0],
                              UITextAttributeTextShadowColor:[UIColor whiteColor],
                              UITextAttributeTextShadowOffset:[NSValue valueWithUIOffset:UIOffsetMake(0.0, 0.0)],
                              UITextAttributeFont:[UIFont fontWithName:@"HelveticaNeue-Light" size:17.0]}
     forState:UIControlStateHighlighted];

    [[UIBarButtonItem appearanceWhenContainedIn:[UINavigationBar class], nil]
     setTitleTextAttributes:@{UITextAttributeTextColor:[UIColor lightGrayColor],
                              UITextAttributeTextShadowColor:[UIColor whiteColor],
                              UITextAttributeTextShadowOffset:[NSValue valueWithUIOffset:UIOffsetMake(0.0, 0.0)],
                              UITextAttributeFont:[UIFont fontWithName:@"HelveticaNeue-Light" size:17.0]}
     forState:UIControlStateDisabled];

    [[UIBarButtonItem appearanceWhenContainedIn:[UINavigationBar class], nil]
     setBackgroundImage:[[UIImage imageNamed:@"button-bg-clear.png"]
                         resizableImageWithCapInsets:UIEdgeInsetsMake(14.0, 5.0, 16.0, 5.0)]
     forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];

    [[UIBarButtonItem appearanceWhenContainedIn:[UINavigationBar class], nil]
     setBackButtonBackgroundImage:[[UIImage imageNamed:@"back-bg.png"]
                                   resizableImageWithCapInsets:UIEdgeInsetsMake(14.0, 15.0, 16.0, 5.0)]
     forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];

    [[UIBarButtonItem appearanceWhenContainedIn:[UINavigationBar class], nil]
     setBackButtonBackgroundImage:[[UIImage imageNamed:@"back-bg-pressed.png"]
                                   resizableImageWithCapInsets:UIEdgeInsetsMake(15.0, 15.0, 15.0, 5.0)]
     forState:UIControlStateHighlighted barMetrics:UIBarMetricsDefault];

    [[UIBarButtonItem appearanceWhenContainedIn:[UINavigationBar class], nil]
     setBackButtonTitlePositionAdjustment:UIOffsetMake(1.0, -3.0) forBarMetrics:UIBarMetricsDefault];
}

#pragma mark - CBCentralManagerDelegate

- (void)centralManagerDidUpdateState:(CBCentralManager *)cbManager
{
    switch (cbManager.state) {
        case CBCentralManagerStateResetting: NSLog(@"system BT connection momentarily lost."); break;
        case CBCentralManagerStateUnsupported: NSLog(@"BT Low Energy not suppoerted."); break;
        case CBCentralManagerStateUnauthorized: NSLog(@"BT Low Energy not authorized."); break;
        case CBCentralManagerStatePoweredOff: NSLog(@"BT off."); break;
        case CBCentralManagerStatePoweredOn: NSLog(@"BT on."); break;
        default: NSLog(@"BT State unknown."); break;
    }    
}
@end
