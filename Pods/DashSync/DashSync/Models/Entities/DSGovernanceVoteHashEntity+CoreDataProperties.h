//
//  DSGovernanceVoteHashEntity+CoreDataProperties.h
//  DashSync
//
//  Created by Sam Westrich on 6/15/18.
//
//

#import "DSGovernanceVoteHashEntity+CoreDataClass.h"


NS_ASSUME_NONNULL_BEGIN

@interface DSGovernanceVoteHashEntity (CoreDataProperties)

+ (NSFetchRequest<DSGovernanceVoteHashEntity *> *)fetchRequest;

@property (nullable, nonatomic, retain) NSData *governanceVoteHash;
@property (nonatomic, assign) uint64_t timestamp;
@property (nullable, nonatomic, retain) DSGovernanceVoteEntity *governanceVote;
@property (nullable, nonatomic, retain) DSChainEntity *chain;
@property (nullable, nonatomic, retain) DSGovernanceObjectEntity *governanceObject;

@end

NS_ASSUME_NONNULL_END
