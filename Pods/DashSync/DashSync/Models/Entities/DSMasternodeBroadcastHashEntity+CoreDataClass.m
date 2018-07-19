//
//  DSMasternodeBroadcastHashEntity+CoreDataClass.m
//  DashSync
//
//  Created by Sam Westrich on 6/8/18.
//
//

#import "DSMasternodeBroadcastHashEntity+CoreDataClass.h"
#import "DSChainEntity+CoreDataClass.h"
#import "NSManagedObject+Sugar.h"

@implementation DSMasternodeBroadcastHashEntity

+(NSArray*)masternodeBroadcastHashEntitiesWithHashes:(NSOrderedSet*)masternodeBroadcastHashes onChain:(DSChainEntity*)chainEntity {
    NSMutableArray * rArray = [NSMutableArray arrayWithCapacity:masternodeBroadcastHashes.count];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    for (NSData * masternodeBroadcastHash in masternodeBroadcastHashes) {
        DSMasternodeBroadcastHashEntity * masternodeBroadcastHashEntity = [self managedObject];
        masternodeBroadcastHashEntity.masternodeBroadcastHash = masternodeBroadcastHash;
        masternodeBroadcastHashEntity.timestamp = now;
        masternodeBroadcastHashEntity.chain = chainEntity;
        [rArray addObject:masternodeBroadcastHashEntity];
    }
    return [rArray copy];
}

+(void)updateTimestampForMasternodeBroadcastHashEntitiesWithMasternodeBroadcastHashes:(NSOrderedSet*)masternodeBroadcastHashes onChain:(DSChainEntity*)chainEntity {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSArray * entitiesToUpdate = [self objectsMatching:@"(chain == %@) && (masternodeBroadcastHash in %@)",chainEntity,masternodeBroadcastHashes];
    for (DSMasternodeBroadcastHashEntity * entityToUpdate in entitiesToUpdate) {
        entityToUpdate.timestamp = now;
    }
}

+(void)removeOldest:(NSUInteger)count onChain:(DSChainEntity*)chainEntity {
    NSLog(@"Removing oldest masternodes %lu",(unsigned long)count);
    NSFetchRequest * fetchRequest = [self fetchReq];
    [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"chain == %@",chainEntity]];
    [fetchRequest setFetchLimit:count];
    [fetchRequest setSortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:TRUE]]];
    NSArray * oldObjects = [self fetchObjects:fetchRequest];
    for (NSManagedObject *obj in oldObjects) {
        [self.context deleteObject:obj];
    }
}

+(NSUInteger)countAroundNowOnChain:(DSChainEntity*)chainEntity {
    NSTimeInterval aMinuteAgo = [[NSDate date] timeIntervalSince1970] - 60;
    return [self countObjectsMatching:@"chain == %@ && timestamp > %@",chainEntity,@(aMinuteAgo)];
}

+(NSUInteger)standaloneCountInLast3hoursOnChain:(DSChainEntity*)chainEntity {
    NSTimeInterval threeHoursAgo = [[NSDate date] timeIntervalSince1970] - 10800;
    return [self countObjectsMatching:@"chain == %@ && timestamp > %@ && masternodeBroadcast == nil",chainEntity,@(threeHoursAgo)];
}

+ (void)deleteHashesOnChain:(DSChainEntity*)chainEntity {
    [chainEntity.managedObjectContext performBlockAndWait:^{
        NSArray * hashesToDelete = [self objectsMatching:@"(chain == %@)",chainEntity];
        for (DSMasternodeBroadcastHashEntity * masternodeBroadcastHashEntity in hashesToDelete) {
            [chainEntity.managedObjectContext deleteObject:masternodeBroadcastHashEntity];
        }
    }];
}


@end
