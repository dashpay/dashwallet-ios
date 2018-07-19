//
//  DSMasternodeBroadcastHashEntity+CoreDataClass.h
//  DashSync
//
//  Created by Sam Westrich on 6/8/18.
//
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class DSMasternodeBroadcastEntity, DSChainEntity;

NS_ASSUME_NONNULL_BEGIN

@interface DSMasternodeBroadcastHashEntity : NSManagedObject

+(NSArray*)masternodeBroadcastHashEntitiesWithHashes:(NSOrderedSet*)masternodeBroadcastHashes onChain:(DSChainEntity*)chainEntity;
+(void)updateTimestampForMasternodeBroadcastHashEntitiesWithMasternodeBroadcastHashes:(NSOrderedSet*)masternodeBroadcastHashes onChain:(DSChainEntity*)chainEntity;
+(void)removeOldest:(NSUInteger)count onChain:(DSChainEntity*)chainEntity;
+(NSUInteger)countAroundNowOnChain:(DSChainEntity*)chainEntity;
+(NSUInteger)standaloneCountInLast3hoursOnChain:(DSChainEntity*)chainEntity;
+(void)deleteHashesOnChain:(DSChainEntity*)chainEntity;

@end

NS_ASSUME_NONNULL_END

#import "DSMasternodeBroadcastHashEntity+CoreDataProperties.h"
