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
#import <MessageUI/MessageUI.h>

@implementation ZNAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Override point for customization after application launch.

    [self keepUpAppearances];

    //TODO: implement testnet build
    
    //TODO: digitally sign every source release
    
    //TODO: upgrade openssl (and other libs) to latest
    
    //TODO: implement pin code

    //TODO: network status indicator perferrably tied to websocket status
    
    //TODO: figure what to do about bluetooth
    // this will notify user if bluetooth is disabled (on 4S and newer devices that support BTLE)
    //CBCentralManager *cbManager = [[CBCentralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue()];
    
    //[self centralManagerDidUpdateState:cbManager]; // Show initial state
    
    return YES;
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
