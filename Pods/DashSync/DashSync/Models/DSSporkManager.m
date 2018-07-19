//
//  DSSporkManager.m
//  dashwallet
//
//  Created by Sam Westrich on 10/18/17.
//  Copyright © 2017 Aaron Voisine. All rights reserved.
//

#import "DSSporkManager.h"
#import "DSSpork.h"
#import "DSSporkHashEntity+CoreDataProperties.h"
#import "DSSporkEntity+CoreDataProperties.h"
#import "NSManagedObject+Sugar.h"
#import "DSChain.h"
#import "DSChainEntity+CoreDataProperties.h"
#import "DSChainPeerManager.h"

@interface DSSporkManager()
    
@property (nonatomic,strong) NSMutableDictionary * sporkDictionary;
@property (nonatomic,strong) NSMutableArray * sporkHashesMarkedForRetrieval;
@property (nonatomic,strong) DSChain * chain;
@property (nonatomic,strong) NSManagedObjectContext * managedObjectContext;
    
@end

@implementation DSSporkManager

- (instancetype)initWithChain:(id)chain
{
    if (! (self = [super init])) return nil;
    _chain = chain;
    __block NSMutableArray * sporkHashesMarkedForRetrieval = [NSMutableArray array];
    __block NSMutableDictionary * sporkDictionary = [NSMutableDictionary dictionary];
    self.managedObjectContext = [NSManagedObject context];
    [self.managedObjectContext performBlockAndWait:^{
        [DSChainEntity setContext:self.managedObjectContext];
        DSChainEntity * chainEntity = self.chain.chainEntity;
        NSArray * sporkEntities = [DSSporkEntity sporksOnChain:chainEntity];
        for (DSSporkEntity * sporkEntity in sporkEntities) {
            DSSpork * spork = [[DSSpork alloc] initWithIdentifier:sporkEntity.identifier value:sporkEntity.value timeSigned:sporkEntity.timeSigned signature:sporkEntity.signature onChain:chain];
            sporkDictionary[@(spork.identifier)] = spork;
        }
        NSArray * sporkHashEntities = [DSSporkHashEntity standaloneSporkHashEntitiesOnChain:chainEntity];
        for (DSSporkHashEntity * sporkHashEntity in sporkHashEntities) {
            [sporkHashesMarkedForRetrieval addObject:sporkHashEntity.sporkHash];
        }
    }];
    _sporkDictionary = sporkDictionary;
    _sporkHashesMarkedForRetrieval = sporkHashesMarkedForRetrieval;
    return self;
}
    
-(BOOL)instantSendActive {
    DSSpork * instantSendSpork = self.sporkDictionary[@(DSSporkIdentifier_Spork2InstantSendEnabled)];
    if (!instantSendSpork) return TRUE;//assume true
    return !!instantSendSpork.value;
}

-(BOOL)sporksUpdatedSignatures {
    DSSpork * updateSignatureSpork = self.sporkDictionary[@(DSSporkIdentifier_Spork6NewSigs)];
    if (!updateSignatureSpork) return FALSE;//assume true
    return !!updateSignatureSpork.value;
}



-(NSDictionary*)sporkDictionary {
    return [_sporkDictionary copy];
}

- (void)peer:(DSPeer * _Nonnull)peer hasSporkHashes:(NSSet* _Nonnull)sporkHashes {
    BOOL hasNew = FALSE;
    for (NSData * sporkHash in sporkHashes) {
        if (![_sporkHashesMarkedForRetrieval containsObject:sporkHash]) {
            [_sporkHashesMarkedForRetrieval addObject:sporkHash];
            hasNew = TRUE;
        }
    }
    if (hasNew) [self.chain.peerManagerDelegate getSporks];
}
    
- (void)peer:(DSPeer *)peer relayedSpork:(DSSpork *)spork {
    if (!spork.isValid) return; //sanity check
    DSSpork * currentSpork = self.sporkDictionary[@(spork.identifier)];
    BOOL updatedSpork = FALSE;
    __block NSMutableDictionary * dictionary = [[NSMutableDictionary alloc] init];
    if (currentSpork) {
        //there was already a spork
        if (![currentSpork isEqualToSpork:spork]) {
            _sporkDictionary[@(spork.identifier)] = spork; //set it to new one
            updatedSpork = TRUE;
            [dictionary setObject:currentSpork forKey:@"old"];
        } else {
            return; //nothing more to do
        }
    } else {
        _sporkDictionary[@(spork.identifier)] = spork;
    }
    [dictionary setObject:spork forKey:@"new"];
    [dictionary setObject:self.chain forKey:DSChainPeerManagerNotificationChainKey];
    if (!currentSpork || updatedSpork) {
        @autoreleasepool {
            [[DSSporkEntity managedObject] setAttributesFromSpork:spork]; // add new peers
            [DSSporkEntity saveContext];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:DSSporkListDidUpdateNotification object:nil userInfo:dictionary];
        });
    }
}



-(void)wipeSporkInfo {
    _sporkDictionary = [NSMutableDictionary dictionary];
}
    
@end
