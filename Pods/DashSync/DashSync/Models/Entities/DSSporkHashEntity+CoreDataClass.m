//
//  DSSporkHashEntity+CoreDataClass.m
//  DashSync
//
//  Created by Sam Westrich on 7/17/18.
//
//

#import "DSSporkHashEntity+CoreDataClass.h"
#import "NSManagedObject+Sugar.h"

@implementation DSSporkHashEntity

+(DSSporkHashEntity*)sporkHashEntityWithHash:(NSData*)sporkHash onChain:(DSChainEntity*)chainEntity {
    return [[self sporkHashEntitiesWithHash:[NSOrderedSet orderedSetWithObject:sporkHash] onChain:chainEntity] firstObject];
}

+(NSArray*)sporkHashEntitiesWithHash:(NSOrderedSet*)sporkHashes onChain:(DSChainEntity*)chainEntity {
    NSAssert(chainEntity, @"chain entity is not set");
    NSMutableArray * rArray = [NSMutableArray arrayWithCapacity:sporkHashes.count];
    for (NSData * sporkHash in sporkHashes) {
        NSArray * sporkHashesFromDisk = [self objectsMatching:@"sporkHash = %@",sporkHash];
        if ([sporkHashesFromDisk count]) {
            [rArray addObject:[sporkHashesFromDisk firstObject]];
        } else {
            DSSporkHashEntity * sporkHashEntity = [self managedObject];
            sporkHashEntity.sporkHash = sporkHash;
            sporkHashEntity.chain = chainEntity;
            [rArray addObject:sporkHashEntity];
        }
    }
    return [rArray copy];
}

+(NSArray*)standaloneSporkHashEntitiesOnChain:(DSChainEntity*)chainEntity {
    NSFetchRequest * fetchRequest = [self fetchReq];
    [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"chain == %@ && sporkHash = nil",chainEntity]];
    NSArray * standaloneHashes = [self fetchObjects:fetchRequest];
    return standaloneHashes;
}

@end
