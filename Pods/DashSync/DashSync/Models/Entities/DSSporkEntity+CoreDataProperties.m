//
//  DSSporkEntity+CoreDataProperties.m
//  DashSync
//
//  Created by Sam Westrich on 5/28/18.
//
//

#import "DSSporkEntity+CoreDataProperties.h"

@implementation DSSporkEntity (CoreDataProperties)

+ (NSFetchRequest<DSSporkEntity *> *)fetchRequest {
	return [NSFetchRequest fetchRequestWithEntityName:@"DSSporkEntity"];
}

@dynamic identifier;
@dynamic signature;
@dynamic timeSigned;
@dynamic value;
@dynamic sporkHash;

@end
