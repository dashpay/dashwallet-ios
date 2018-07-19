//
//  DSGovernanceVoteHashEntity+CoreDataClass.h
//  DashSync
//
//  Created by Sam Westrich on 6/15/18.
//
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class DSChainEntity, DSGovernanceVoteEntity, DSGovernanceObjectEntity;

NS_ASSUME_NONNULL_BEGIN

@interface DSGovernanceVoteHashEntity : NSManagedObject

+(NSArray*)governanceVoteHashEntitiesWithHashes:(NSOrderedSet*)governanceVoteHashes forGovernanceObject:(DSGovernanceObjectEntity*)governanceObject;
+(void)updateTimestampForGovernanceVoteHashEntitiesWithGovernanceVoteHashes:(NSOrderedSet*)governanceVoteHashes forGovernanceObject:(DSGovernanceObjectEntity*)governanceObject;
+(void)removeOldest:(NSUInteger)count hashesNotIn:(NSSet*)governanceVoteHashes forGovernanceObject:(DSGovernanceObjectEntity*)governanceObject;
+(NSUInteger)countAroundNowOnChain:(DSChainEntity*)chainEntity;
+(NSUInteger)standaloneCountInLast3hoursOnChain:(DSChainEntity*)chainEntity;
+(void)deleteHashesOnChain:(DSChainEntity*)chainEntity;

@end

NS_ASSUME_NONNULL_END

#import "DSGovernanceVoteHashEntity+CoreDataProperties.h"
