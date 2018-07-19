//
//  DSMasternodeBroadcastEntity+CoreDataClass.m
//  DashSync
//
//  Created by Sam Westrich on 6/4/18.
//
//

#import "DSMasternodeBroadcastEntity+CoreDataClass.h"
#import "DSMasternodeBroadcastHashEntity+CoreDataClass.h"
#import "NSManagedObject+Sugar.h"
#import "DSChainEntity+CoreDataClass.h"
#import "NSData+Dash.h"

@implementation DSMasternodeBroadcastEntity

- (void)setAttributesFromMasternodeBroadcast:(DSMasternodeBroadcast *)masternodeBroadcast forHashEntity:(DSMasternodeBroadcastHashEntity*)hashEntity {
    [self.managedObjectContext performBlockAndWait:^{
        self.utxoHash = [NSData dataWithBytes:masternodeBroadcast.utxo.hash.u8 length:sizeof(UInt256)];
        self.utxoIndex = (uint32_t)masternodeBroadcast.utxo.n;
        self.address = masternodeBroadcast.ipAddress.u32[3];
        self.masternodeBroadcastHash = hashEntity;
        self.port = masternodeBroadcast.port;
        self.protocolVersion = masternodeBroadcast.protocolVersion;
        self.signature = masternodeBroadcast.signature;
        self.signatureTimestamp = masternodeBroadcast.signatureTimestamp;
        self.publicKey = masternodeBroadcast.publicKey;
        self.uniqueID = [NSData dataWithUInt256:masternodeBroadcast.masternodeBroadcastHash].shortHexString;
    }];
}

+ (NSUInteger)countForChain:(DSChainEntity*)chain {
    __block NSUInteger count = 0;
    [chain.managedObjectContext performBlockAndWait:^{
        NSFetchRequest * fetchRequest = [DSMasternodeBroadcastEntity fetchReq];
        [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"masternodeBroadcastHash.chain = %@",chain]];
        count = [DSMasternodeBroadcastEntity countObjects:fetchRequest];
    }];
    return count;
}

- (DSMasternodeBroadcast*)masternodeBroadcast {
    __block DSMasternodeBroadcast *masternodeBroadcast = nil;
    
    [self.managedObjectContext performBlockAndWait:^{
        UInt128 address = { .u32 = { 0, 0, CFSwapInt32HostToBig(0xffff), CFSwapInt32HostToBig(self.address) } };
        DSChainEntity * chain = [self.masternodeBroadcastHash chain];
        DSUTXO utxo;
        utxo.hash = *(UInt256*)self.utxoHash.bytes;
        utxo.n = self.utxoIndex;
        UInt256 masternodeBroadcastHash = *(UInt256*)self.masternodeBroadcastHash.masternodeBroadcastHash.bytes;
        masternodeBroadcast = [[DSMasternodeBroadcast alloc] initWithUTXO:utxo ipAddress:address port:self.port protocolVersion:self.protocolVersion publicKey:self.publicKey signature:self.signature signatureTimestamp:self.signatureTimestamp masternodeBroadcastHash:masternodeBroadcastHash onChain:[chain chain]];
    }];
    
    return masternodeBroadcast;
}


@end
