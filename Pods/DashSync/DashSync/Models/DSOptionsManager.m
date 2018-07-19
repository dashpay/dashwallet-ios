//
//  DSOptionsManager.m
//  DashSync
//
//  Created by Sam Westrich on 6/5/18.
//

#import "DSOptionsManager.h"

@implementation DSOptionsManager

@dynamic keepHeaders;
@dynamic syncFromHeight;
@dynamic syncGovernanceObjectsInterval;
@dynamic syncMasternodeListInterval;
@dynamic syncType;

+ (instancetype)sharedInstance {
    static DSOptionsManager *_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[self alloc] init];
    });
    return _sharedInstance;
}

- (instancetype)init {
    NSDictionary *defaults = @{
        @"keepHeaders" : @NO,
        @"syncGovernanceObjectsInterval" : @600, // 10 min
        @"syncMasternodeListInterval" : @600,    // 10 min
        @"syncFromHeight" : @0,
        @"syncType" : @(DSSyncType_Default),
    };

    self = [super initWithDefaults:defaults];
    if (self) {
    }
    return self;
}


#pragma mark Manual

- (BOOL)shouldSyncFromHeight {
    NSString *key = @"syncFromHeight";
    return [[self userDefaults] objectForKey:key];
}

- (void)setSyncFromGenesis:(BOOL)syncFromGenesis {
    NSString *key = @"syncFromHeight";
    if (syncFromGenesis) {
        self.syncFromHeight = 0;
    }
    else if ([[self userDefaults] objectForKey:key]) {
        uint32_t height = self.syncFromHeight;
        if (height == 0) {
            [[self userDefaults] removeObjectForKey:key];
        }
    }
}

- (BOOL)syncFromGenesis {
    NSString *key = @"syncFromHeight";
    id syncFromHeight = [[self userDefaults] objectForKey:key];
    if (syncFromHeight) {
        return !self.syncFromHeight;
    }
    else {
        return NO;
    }
}

- (void)addSyncType:(DSSyncType)addSyncType {
    self.syncType = self.syncType | addSyncType;
}

- (void)clearSyncType:(DSSyncType)clearSyncType {
    self.syncType = self.syncType & ~clearSyncType;
}

@end
