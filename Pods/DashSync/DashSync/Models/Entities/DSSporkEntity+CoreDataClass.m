//
//  DSSporkEntity+CoreDataClass.m
//  DashSync
//
//  Created by Sam Westrich on 5/28/18.
//
//

#import "DSSporkEntity+CoreDataClass.h"
#import "DSSpork.h"
#import "DSChain.h"
#import "DSSporkHashEntity+CoreDataClass.h"
#import "DSChainEntity+CoreDataClass.h"
#import "NSManagedObject+Sugar.h"
#import "NSData+Bitcoin.h"

@implementation DSSporkEntity

- (void)setAttributesFromSpork:(DSSpork *)spork
{
    [self.managedObjectContext performBlockAndWait:^{
        [DSChainEntity setContext:self.managedObjectContext];
        [DSSporkHashEntity setContext:self.managedObjectContext];
        self.identifier = spork.identifier;
        self.signature = spork.signature;
        self.timeSigned = spork.timeSigned;
        self.value = spork.value;
        self.sporkHash = [DSSporkHashEntity sporkHashEntityWithHash:[NSData dataWithUInt256:spork.sporkHash] onChain:spork.chain.chainEntity];
    }];
}

+ (NSArray<DSSporkEntity*>*)sporksOnChain:(DSChainEntity*)chainEntity {
    __block NSArray * sporksOnChain;
    [chainEntity.managedObjectContext performBlockAndWait:^{
        sporksOnChain = [self objectsMatching:@"(sporkHash.chain == %@)",chainEntity];
    }];
    return sporksOnChain;
}

+ (void)deleteSporksOnChain:(DSChainEntity*)chainEntity {
    [chainEntity.managedObjectContext performBlockAndWait:^{
        NSArray * sporksToDelete = [self objectsMatching:@"(sporkHash.chain == %@)",chainEntity];
        for (DSSporkEntity * sporkEntity in sporksToDelete) {
            [chainEntity.managedObjectContext deleteObject:sporkEntity];
        }
    }];
}

@end
