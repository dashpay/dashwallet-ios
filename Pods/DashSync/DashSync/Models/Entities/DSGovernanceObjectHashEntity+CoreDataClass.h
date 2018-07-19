//
//  DSGovernanceObjectHashEntity+CoreDataClass.h
//  DashSync
//
//  Created by Sam Westrich on 6/14/18.
//
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class DSChainEntity, DSGovernanceObjectEntity;

NS_ASSUME_NONNULL_BEGIN

@interface DSGovernanceObjectHashEntity : NSManagedObject

+(DSGovernanceObjectHashEntity*)governanceObjectHashEntityWithHash:(NSData*)governanceObjectHash onChain:(DSChainEntity*)chainEntity;
+(NSArray*)governanceObjectHashEntitiesWithHashes:(NSOrderedSet*)governanceObjectHashes onChain:(DSChainEntity*)chainEntity;
+(void)updateTimestampForGovernanceObjectHashEntitiesWithGovernanceObjectHashes:(NSOrderedSet*)governanceObjectHashes onChain:(DSChainEntity*)chainEntity;
+(void)removeOldest:(NSUInteger)count onChain:(DSChainEntity*)chainEntity;
+(NSUInteger)countAroundNowOnChain:(DSChainEntity*)chainEntity;
+(NSUInteger)standaloneCountInLast3hoursOnChain:(DSChainEntity*)chainEntity;
+(void)deleteHashesOnChain:(DSChainEntity*)chainEntity;

@end

NS_ASSUME_NONNULL_END

#import "DSGovernanceObjectHashEntity+CoreDataProperties.h"
