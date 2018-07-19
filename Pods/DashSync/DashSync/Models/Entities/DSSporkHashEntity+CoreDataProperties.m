//
//  DSSporkHashEntity+CoreDataProperties.m
//  DashSync
//
//  Created by Sam Westrich on 7/17/18.
//
//

#import "DSSporkHashEntity+CoreDataProperties.h"

@implementation DSSporkHashEntity (CoreDataProperties)

+ (NSFetchRequest<DSSporkHashEntity *> *)fetchRequest {
	return [NSFetchRequest fetchRequestWithEntityName:@"DSSporkHashEntity"];
}

@dynamic sporkHash;
@dynamic chain;
@dynamic spork;

@end
