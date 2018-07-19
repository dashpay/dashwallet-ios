//
//  DSGovernanceVoteEntity+CoreDataClass.h
//  DashSync
//
//  Created by Sam Westrich on 6/15/18.
//
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class DSGovernanceObjectEntity, DSGovernanceVoteHashEntity, DSMasternodeBroadcastEntity,DSChainEntity,DSGovernanceVote;

NS_ASSUME_NONNULL_BEGIN

@interface DSGovernanceVoteEntity : NSManagedObject

- (void)setAttributesFromGovernanceVote:(DSGovernanceVote *)governanceVote forHashEntity:(DSGovernanceVoteHashEntity*)hashEntity;
+ (NSUInteger)countForChain:(DSChainEntity* _Nonnull)chain;
+ (NSUInteger)countForGovernanceObject:(DSGovernanceObjectEntity*)governanceObject;
- (DSGovernanceVote*)governanceVote;

@end

NS_ASSUME_NONNULL_END

#import "DSGovernanceVoteEntity+CoreDataProperties.h"
