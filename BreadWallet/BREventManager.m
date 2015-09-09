//
//  BREventManager.m
//  BreadWallet
//
//  Created by Samuel Sutch on 9/8/15.
//  Copyright (c) 2015 Aaron Voisine. All rights reserved.
//

#import "BREventManager.h"
#import "BRPeerManager.h"
#import "BREventConfirmView.h"
#import "UIImage+Utils.h"


@interface BREventManager ()

@property NSString *sessionId;
@property NSOperationQueue *myQueue;
@property NSDictionary *eventToNotifications;

@property NSMutableArray *_buffer;

@end

#define HAS_DETERMINED_SAMPLE_GROUP @"has_determined_sample_group"
#define IS_IN_SAMPLE_GROUP @"is_in_sample_group"
#define HAS_PROMPTED_FOR_PERMISSION @"has_prompted_for_permission"
#define HAS_ACQUIRED_PERMISSION @"has_acquired_permission"
#define SAMPLE_CHANCE 10

@implementation BREventManager

- (instancetype)init
{
    if (self = [super init]) {
        CFUUIDRef uuid = CFUUIDCreate(NULL);
        self.sessionId = (__bridge_transfer NSString *)CFUUIDCreateString(NULL, uuid);
        CFRelease(uuid);
        self.myQueue = [[NSOperationQueue alloc] init];
        self.eventToNotifications = @{@"foreground": UIApplicationDidBecomeActiveNotification,
                                      @"background": UIApplicationDidEnterBackgroundNotification,
                                      @"sync_finished": BRPeerManagerSyncFinishedNotification,
                                      @"sync_failed": BRPeerManagerSyncFailedNotification};
    }
    return self;
}

+ (instancetype)sharedEventManager
{
    static id _sharedEventMgr;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // determine if user is in sample group. it's inside the dispatch_once so it happens
        // exactly once per startup
        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        if (![defs boolForKey:HAS_DETERMINED_SAMPLE_GROUP]) {
            bool isInSample = (arc4random_uniform(100)+1) < SAMPLE_CHANCE;
            [defs setBool:isInSample forKey:IS_IN_SAMPLE_GROUP];
            [defs setBool:YES forKey:HAS_DETERMINED_SAMPLE_GROUP];
        }
        
        // allocate the singleton
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
    // map NSNotifications to events
    [self.eventToNotifications enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [[NSNotificationCenter defaultCenter]
         addObserverForName:obj object:nil queue:self.myQueue
         usingBlock:^(NSNotification *note) {
             [self saveEvent:key];
         }];
    }];
}

- (void)down
{
    // remove listeners for NSNotifications
    [self.eventToNotifications.allValues enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:obj object:nil];
    }];
}

- (void)saveEvent:(NSString *)eventName
{
    [self _pushEventNamed:eventName withAttributes:@{}];
}

- (void)saveEvent:(NSString *)eventName withAttributes:(NSDictionary *)attributes
{
    [self _pushEventNamed:eventName withAttributes:attributes];
}

- (BOOL)isInSampleGroup
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:IS_IN_SAMPLE_GROUP];
}

- (BOOL)hasAcquiredPermission
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:HAS_ACQUIRED_PERMISSION];
}

- (void)acquireUserPermissionInViewController:(UIViewController *)viewController
                                 withCallback:(void (^)(BOOL))completionCallback
{
    UIGraphicsBeginImageContext(viewController.view.bounds.size);
    [viewController.view drawViewHierarchyInRect:viewController.view.bounds afterScreenUpdates:NO];
    UIImage *bgImg = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    UIImage *blurredBgImg = [bgImg blurWithRadius:1.5];
    
    BREventConfirmView *eventConfirmView = [[[NSBundle mainBundle]
                                             loadNibNamed:@"BREventConfirmView" owner:nil options:nil] objectAtIndex:0];
    eventConfirmView.image = blurredBgImg;
    eventConfirmView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    eventConfirmView.frame = viewController.view.bounds;
    eventConfirmView.alpha = 0;
    [viewController.view addSubview:eventConfirmView];
    
    [UIView animateWithDuration:.5 animations:^{
        eventConfirmView.alpha = 1;
    }];
}

# pragma mark -

- (void)_pushEventNamed:(NSString *)evtName withAttributes:(NSDictionary *)attrs
{
    if (!self._buffer) {
        self._buffer = [NSMutableArray array];
    }
#if BITCOIN_TESTNET
    // notify when in test mode
    [attrs enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if (![key isKindOfClass:[NSString class]] || ![obj isKindOfClass:[NSString class]]) {
            NSLog(@"warning: key or value in attributes dictionary is not of type string, "
                  @"will be implicitly converted");
        }
    }];
#endif
    NSMutableDictionary *safeDict = [NSMutableDictionary dictionary];
    [attrs enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [safeDict setObject:[obj description] forKey:[key description]];
    }];
    
    // we push a 3-tuple into the buffer consisting of (current_time, event_name, event_attributes)
    NSArray *tuple = @[[NSNumber numberWithDouble:[NSDate timeIntervalSinceReferenceDate]*1000], evtName, attrs];
    [self._buffer addObject:tuple];
}

@end
