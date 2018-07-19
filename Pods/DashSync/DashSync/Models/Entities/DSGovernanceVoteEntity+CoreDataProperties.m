//
//  DSGovernanceVoteEntity+CoreDataProperties.m
//  DashSync
//
//  Created by Sam Westrich on 6/15/18.
//
//

#import "DSGovernanceVoteEntity+CoreDataProperties.h"

@implementation DSGovernanceVoteEntity (CoreDataProperties)

+ (NSFetchRequest<DSGovernanceVoteEntity *> *)fetchRequest {
	return [NSFetchRequest fetchRequestWithEntityName:@"DSGovernanceVoteEntity"];
}

@dynamic outcome;
@dynamic signal;
@dynamic timestampCreated;
@dynamic signature;
@dynamic masternodeHash;
@dynamic governanceVoteHash;
@dynamic masternode;
@dynamic parentHash;
@dynamic masternodeIndex;

@end
