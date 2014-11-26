//
//  BRAppDelegate.m
//  BreadWallet
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

#import "BRAppDelegate.h"
#import "BRPeerManager.h"

#if BITCOIN_TESTNET
#warning testnet build
#endif

@implementation BRAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Override point for customization after application launch.

    // use background fetch to stay synced with the blockchain
    // BUG: XXXX this doesn't seem to work, is it compatible with data protection settings?
    [[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalMinimum];

    UIPageControl.appearance.pageIndicatorTintColor = [UIColor lightGrayColor];
    UIPageControl.appearance.currentPageIndicatorTintColor = [UIColor blackColor];

    [[UIBarButtonItem appearanceWhenContainedIn:[UINavigationBar class], nil]
     setTitleTextAttributes:@{NSFontAttributeName:[UIFont fontWithName:@"HelveticaNeue-Light" size:17.0]}
     forState:UIControlStateNormal];

    if (launchOptions[UIApplicationLaunchOptionsURLKey]) {
        NSData *file = [NSData dataWithContentsOfURL:launchOptions[UIApplicationLaunchOptionsURLKey]];

        if (file.length > 0) {
            [[NSNotificationCenter defaultCenter] postNotificationName:BRFileNotification object:nil
             userInfo:@{@"file":file}];
        }
    }

    //TODO: bitcoin protocol/payment protocol over multipeer connectivity

    //TODO: accessibility for the visually impaired

    //TODO: internationalization

    //TODO: fast wallet restore using webservice and/or utxo p2p message

    //TODO: ask user if they need to sweep to a new wallet when restoring because it was compromised

    //TODO: figure out deterministic builds/removing app sigs: http://www.afp548.com/2012/06/05/re-signining-ios-apps/

    return YES;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication
annotation:(id)annotation
{
    if (! [url.scheme isEqual:@"bitcoin"] && ! [url.scheme isEqual:@"bread"]) {
        [[[UIAlertView alloc] initWithTitle:@"Not a bitcoin URL" message:url.absoluteString delegate:nil
          cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        return NO;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC/10), dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:BRURLNotification object:nil userInfo:@{@"url":url}];
    });
    
    return YES;
}

- (void)application:(UIApplication *)application
performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler
{
    __block id syncFinishedObserver = nil, syncFailedObserver = nil, protectedObserver = nil;
    __block void (^completion)(UIBackgroundFetchResult) = completionHandler;
    BRPeerManager *m = [BRPeerManager sharedInstance];

    if (m.syncProgress >= 1.0) {
        if (completion) completion(UIBackgroundFetchResultNoData);
        return;
    }

    // timeout after 25 seconds
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 25*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (completion) {
            completion(m.syncProgress > 0.1 ? UIBackgroundFetchResultNewData : UIBackgroundFetchResultFailed);
            completion = nil;
        }

        if (protectedObserver) [[NSNotificationCenter defaultCenter] removeObserver:protectedObserver];
        if (syncFinishedObserver) [[NSNotificationCenter defaultCenter] removeObserver:syncFinishedObserver];
        if (syncFailedObserver) [[NSNotificationCenter defaultCenter] removeObserver:syncFailedObserver];
        protectedObserver = syncFinishedObserver = syncFailedObserver = nil;
        //TODO: disconnect
    });

    protectedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationProtectedDataDidBecomeAvailable object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            [m connect];
        }];

    syncFinishedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerSyncFinishedNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            if (completion) completion(UIBackgroundFetchResultNewData);
            completion = nil;
            
            if (protectedObserver) [[NSNotificationCenter defaultCenter] removeObserver:protectedObserver];
            if (syncFinishedObserver) [[NSNotificationCenter defaultCenter] removeObserver:syncFinishedObserver];
            if (syncFailedObserver) [[NSNotificationCenter defaultCenter] removeObserver:syncFailedObserver];
            protectedObserver = syncFinishedObserver = syncFailedObserver = nil;
        }];

    syncFailedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerSyncFailedNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            if (completion) completion(UIBackgroundFetchResultFailed);
            completion = nil;

            if (protectedObserver) [[NSNotificationCenter defaultCenter] removeObserver:protectedObserver];
            if (syncFinishedObserver) [[NSNotificationCenter defaultCenter] removeObserver:syncFinishedObserver];
            if (syncFailedObserver) [[NSNotificationCenter defaultCenter] removeObserver:syncFailedObserver];
            protectedObserver = syncFinishedObserver = syncFailedObserver = nil;
        }];
    
    [m connect];
}

@end
