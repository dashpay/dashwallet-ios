//
//  DSMasternodeBroadcastEntity+CoreDataClass.h
//  DashSync
//
//  Created by Sam Westrich on 6/4/18.
//
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "DSMasternodeBroadcast.h"

NS_ASSUME_NONNULL_BEGIN

@class DSChainEntity,DSMasternodeBroadcastHashEntity;

@interface DSMasternodeBroadcastEntity : NSManagedObject

- (void)setAttributesFromMasternodeBroadcast:(DSMasternodeBroadcast *)masternodeBroadcast forHashEntity:(DSMasternodeBroadcastHashEntity*)hashEntity;
+ (NSUInteger)countForChain:(DSChainEntity* _Nonnull)chain;
- (DSMasternodeBroadcast*)masternodeBroadcast;

@end

NS_ASSUME_NONNULL_END

#import "DSMasternodeBroadcastEntity+CoreDataProperties.h"
