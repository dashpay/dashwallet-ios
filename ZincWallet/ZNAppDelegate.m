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
    
    //TODO: implement pin code

    //TODO: network status indicator perferrably tied to websocket status
    
    //TODO: SPV mode (with a build option limiting it to one or two trusted peers for app store compatibility)
    
    //TODO: accessibility for the visually impaired
    
    //TODO: internationalization
    
    // this will notify user if bluetooth is disabled (on 4S and newer devices that support BTLE)
    //CBCentralManager *cbManager = [[CBCentralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue()];
    
    //[self centralManagerDidUpdateState:cbManager]; // Show initial state
    
    return YES;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication
annotation:(id)annotation
{
    NSURL *u = url;
    
    if (! u.host && u.resourceSpecifier) {
        u = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@", u.scheme, u.resourceSpecifier]];
    }

    if (! [u.scheme isEqual:@"bitcoin"]) {
        [[[UIAlertView alloc] initWithTitle:@"Not a bitcoin URL" message:url.absoluteString delegate:nil
          cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        return NO;
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:bitcoinURLNotification object:nil userInfo:@{@"url":u}];
    
    return YES;
}

#pragma mark - appearance

- (void)keepUpAppearances
{
    [[UINavigationBar appearance]
     setTitleTextAttributes:@{NSForegroundColorAttributeName:[UIColor grayColor],
                              NSFontAttributeName:[UIFont fontWithName:@"HelveticaNeue" size:17.0]}];

    [[UIBarButtonItem appearanceWhenContainedIn:[UINavigationBar class], nil]
     setTitleTextAttributes:@{NSFontAttributeName:[UIFont fontWithName:@"HelveticaNeue-Light" size:17.0]}
     forState:UIControlStateNormal];
}

//#pragma mark - CBCentralManagerDelegate
//
//- (void)centralManagerDidUpdateState:(CBCentralManager *)cbManager
//{
//    switch (cbManager.state) {
//        case CBCentralManagerStateResetting: NSLog(@"system BT connection momentarily lost."); break;
//        case CBCentralManagerStateUnsupported: NSLog(@"BT Low Energy not suppoerted."); break;
//        case CBCentralManagerStateUnauthorized: NSLog(@"BT Low Energy not authorized."); break;
//        case CBCentralManagerStatePoweredOff: NSLog(@"BT off."); break;
//        case CBCentralManagerStatePoweredOn: NSLog(@"BT on."); break;
//        default: NSLog(@"BT State unknown."); break;
//    }    
//}
@end
