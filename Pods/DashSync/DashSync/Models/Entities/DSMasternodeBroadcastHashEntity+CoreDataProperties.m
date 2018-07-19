//
//  DSMasternodeBroadcastHashEntity+CoreDataProperties.m
//  DashSync
//
//  Created by Sam Westrich on 6/8/18.
//
//

#import "DSMasternodeBroadcastHashEntity+CoreDataProperties.h"

@implementation DSMasternodeBroadcastHashEntity (CoreDataProperties)

+ (NSFetchRequest<DSMasternodeBroadcastHashEntity *> *)fetchRequest {
	return [NSFetchRequest fetchRequestWithEntityName:@"DSMasternodeBroadcastHashEntity"];
}

@dynamic masternodeBroadcastHash;
@dynamic masternodeBroadcast;
@dynamic chain;
@dynamic timestamp;

@end
