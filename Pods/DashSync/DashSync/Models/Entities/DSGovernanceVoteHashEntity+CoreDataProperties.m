//
//  DSGovernanceVoteHashEntity+CoreDataProperties.m
//  DashSync
//
//  Created by Sam Westrich on 6/15/18.
//
//

#import "DSGovernanceVoteHashEntity+CoreDataProperties.h"

@implementation DSGovernanceVoteHashEntity (CoreDataProperties)

+ (NSFetchRequest<DSGovernanceVoteHashEntity *> *)fetchRequest {
	return [NSFetchRequest fetchRequestWithEntityName:@"DSGovernanceVoteHashEntity"];
}

@dynamic governanceVoteHash;
@dynamic timestamp;
@dynamic governanceVote;
@dynamic chain;
@dynamic governanceObject;

@end
