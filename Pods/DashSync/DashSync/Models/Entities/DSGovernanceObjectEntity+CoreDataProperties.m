//
//  DSGovernanceObjectEntity+CoreDataProperties.m
//  DashSync
//
//  Created by Sam Westrich on 6/14/18.
//
//

#import "DSGovernanceObjectEntity+CoreDataProperties.h"

@implementation DSGovernanceObjectEntity (CoreDataProperties)

+ (NSFetchRequest<DSGovernanceObjectEntity *> *)fetchRequest {
	return [NSFetchRequest fetchRequestWithEntityName:@"DSGovernanceObjectEntity"];
}

@dynamic collateralHash;
@dynamic parentHash;
@dynamic revision;
@dynamic signature;
@dynamic timestamp;
@dynamic type;
@dynamic governanceObjectHash;
@dynamic identifier;
@dynamic amount;
@dynamic endEpoch;
@dynamic startEpoch;
@dynamic url;
@dynamic paymentAddress;
@dynamic voteHashes;
@dynamic totalVotesCount;

@end
