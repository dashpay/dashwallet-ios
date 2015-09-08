//
//  BREventManager.h
//  BreadWallet
//
//  Created by Samuel Sutch on 9/8/15.
//  Copyright (c) 2015 Aaron Voisine. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface BREventManager : NSObject

// typtically this class is used as a singleton so this is how you should get a handle on the global event manager
+ (instancetype)sharedEventManager;

// convenience method for [[BREventManager sharedEventManager] saveEvent:(NSString*)]
+ (void)saveEvent:(NSString *)eventName;

// starts the event manager and begins listening to app lifecycle events if the user has both:
//   1: is in the sample group
//   2: has agreed to be in the sample group
- (void)up;

// quits the event manager, unhooking from all app lifecycle events
- (void)down;

// persists an event to storage to later be sent to the server in a batch
- (void)saveEvent:(NSString *)eventName;

// returns whether or not this instance of BREventManager has been selected to be in a sample group
- (BOOL)isInSampleGroup;

// returns whether or not (if this instance is in the sample group) we have acquired permission from the
// user of the application before
- (BOOL)hasAcquiredPermission;

// displays a UI in the view controller prompting the user for permission to save event data
// the value of whether or not the user agrees will be returned to the completionCallback
- (void)acquireUserPermissionInViewController:(UIViewController *)viewController
                                 withCallback:(void (^)(BOOL didGetPermission))completionCallback;


@end
