//
//  BREventManager.m
//  BreadWallet
//
//  Created by Samuel Sutch on 9/8/15.
//  Copyright (c) 2015 Aaron Voisine. All rights reserved.
//

#import "BREventManager.h"

@interface BREventManager ()

@property NSString *sessionId;
@property NSOperationQueue *myQueue;

@end

@implementation BREventManager

- (instancetype)init
{
    if (self = [super init]) {
        self.myQueue = [[NSOperationQueue alloc] init];
    }
    return self;
}

+ (instancetype)sharedEventManager
{
    static id _sharedEventMgr;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedEventMgr = [[self alloc] init];
    });
    return _sharedEventMgr;
}

+ (void)saveEvent:(NSString *)eventName
{
    [[self sharedEventManager] saveEvent:eventName];
}

- (void)up
{
    [[NSNotificationCenter defaultCenter]
     addObserverForName:UIApplicationDidBecomeActiveNotification
     object:nil queue:self.myQueue
     usingBlock:^(NSNotification *note) {
         CFUUIDRef uuid = CFUUIDCreate(NULL);
         self.sessionId = (__bridge_transfer NSString *)CFUUIDCreateString(NULL, uuid);
         CFRelease(uuid);
         [self saveEvent:@"foreground"];
     }];
    
    [[NSNotificationCenter defaultCenter]
     addObserverForName:UIApplicationDidEnterBackgroundNotification
     object:nil queue:self.myQueue
     usingBlock:^(NSNotification *note) {
         [self saveEvent:@"background"];
         self.sessionId = nil;
     }];
}

- (void)down
{
    [[NSNotificationCenter defaultCenter]
     removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter]
     removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
}

- (void)saveEvent:(NSString *)eventName
{
    // do stuff
}

- (BOOL)isInSampleGroup
{
    return NO;
}

- (BOOL)hasAcquiredPermission
{
    return NO;
}

- (void)acquireUserPermissionInViewController:(UIViewController *)viewController
                                 withCallback:(void (^)(BOOL))completionCallback
{
    // do stuff
}

@end
