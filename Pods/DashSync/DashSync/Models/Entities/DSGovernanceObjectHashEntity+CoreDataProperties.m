//
//  DSGovernanceObjectHashEntity+CoreDataProperties.m
//  DashSync
//
//  Created by Sam Westrich on 6/14/18.
//
//

#import "DSGovernanceObjectHashEntity+CoreDataProperties.h"

@implementation DSGovernanceObjectHashEntity (CoreDataProperties)

+ (NSFetchRequest<DSGovernanceObjectHashEntity *> *)fetchRequest {
	return [NSFetchRequest fetchRequestWithEntityName:@"DSGovernanceObjectHashEntity"];
}

@dynamic governanceObjectHash;
@dynamic timestamp;
@dynamic chain;
@dynamic governanceObject;

@end
