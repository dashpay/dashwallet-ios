//
//  DSMasternodeBroadcast.m
//  DashSync
//
//  Created by Sam Westrich on 5/31/18.
//

#import "DSMasternodeBroadcast.h"
#import "NSData+Bitcoin.h"
#import "DSMasternodePing.h"
#import "DSMasternodeBroadcastEntity+CoreDataProperties.h"
#import "DSMasternodeBroadcastHashEntity+CoreDataProperties.h"
#import "NSManagedObject+Sugar.h"

@interface DSMasternodeBroadcast()

@property (nonatomic,assign) DSUTXO utxo;
@property (nonatomic,strong) NSData * signature;
@property (nonatomic,assign) NSTimeInterval signatureTimestamp;
@property (nonatomic,assign) UInt128 ipAddress;
@property (nonatomic,assign) uint16_t port;
@property (nonatomic,assign) uint32_t protocolVersion;
@property (nonatomic,assign) UInt256 masternodeBroadcastHash;
@property (nonatomic,strong) DSChain * chain;

@end

@implementation DSMasternodeBroadcast

+(UInt256)hashWithUTXO:(DSUTXO)masternodeUTXO collateralPublicKey:(NSData*)collateralPublicKey timeStampData:(NSData*)timestampData {
    //hash calculation
    NSMutableData * hashImportantData = [NSMutableData data];
    uint32_t index = (uint32_t)masternodeUTXO.n;
    [hashImportantData appendData:[NSData dataWithUInt256:masternodeUTXO.hash]];
    [hashImportantData appendBytes:&index length:4];
    uint8_t emptyByte = 0;
    uint32_t fullBits = UINT32_MAX;
    [hashImportantData appendBytes:&emptyByte length:1];
    [hashImportantData appendBytes:&fullBits length:4];
    uint8_t length = (uint8_t)collateralPublicKey.length;
    [hashImportantData appendBytes:&length length:1];
    [hashImportantData appendData:collateralPublicKey];
    [hashImportantData appendData:timestampData];
    return hashImportantData.SHA256_2;
}


-(instancetype)initWithUTXO:(DSUTXO)utxo ipAddress:(UInt128)ipAddress port:(uint16_t)port protocolVersion:(uint32_t)protocolVersion publicKey:(NSData*)publicKey signature:(NSData*)signature signatureTimestamp:(NSTimeInterval)signatureTimestamp masternodeBroadcastHash:(UInt256)masternodeBroadcastHash onChain:(DSChain *)chain {
    if (!(self = [super init])) return nil;
    _utxo = utxo;
    _ipAddress = ipAddress;
    _port = port;
    _signature = signature;
    _signatureTimestamp = signatureTimestamp;
    _protocolVersion = protocolVersion;
    _publicKey = publicKey;
    _chain = chain;
    _masternodeBroadcastHash = masternodeBroadcastHash;
    return self;
}

+(DSMasternodeBroadcast*)masternodeBroadcastFromMessage:(NSData *)message onChain:(DSChain *)chain {
    NSUInteger length = message.length;
    DSUTXO masternodeUTXO;
    NSUInteger offset = 0;
    if (length - offset < 32) return nil;
    masternodeUTXO.hash = [message UInt256AtOffset:offset];
    offset += 32;
    if (length - offset < 4) return nil;
    masternodeUTXO.n = [message UInt32AtOffset:offset];
    offset += 4;
    if (chain.protocolVersion < 70209) { //switch to outpoint in 70209
        if (length - offset < 1) return nil;
        uint8_t sigscriptSize = [message UInt8AtOffset:offset];
        offset += 1;
        if (length - offset < 1) return nil;
        //NSData * sigscript = [message subdataWithRange:NSMakeRange(offset, sigscriptSize)];
        offset += sigscriptSize;
        //uint32_t sequenceNumber = [message UInt32AtOffset:offset];
        if (length - offset < 4) return nil;
        offset += 4;
    }
    if (length - offset < 16) return nil;
    UInt128 masternodeAddress = [message UInt128AtOffset:offset];
    offset += 16;
    if (length - offset < 2) return nil;
    uint16_t port = CFSwapInt16BigToHost(*(const uint16_t *)((const uint8_t *)message.bytes + offset));
    offset += 2;
    if (length - offset < 1) return nil;
    //Collateral Public Key
    uint8_t collateralPublicKeySize = [message UInt8AtOffset:offset];
    offset += 1;
    
    if (length - offset < collateralPublicKeySize) return nil;
    //uint8_t collateralPublicKeyType = [message UInt8AtOffset:offset];
    NSData * collateralPublicKey = [message subdataWithRange:NSMakeRange(offset, collateralPublicKeySize)];
    offset += collateralPublicKeySize;
    //Masternode Public Key
    if (length - offset < 1) return nil;
    uint8_t masternodePublicKeySize = [message UInt8AtOffset:offset];
    offset += 1;
    if (length - offset < masternodePublicKeySize) return nil;
    //uint8_t masternodePublicKeyType = [message UInt8AtOffset:offset];
    NSData * masternodePublicKey = [message subdataWithRange:NSMakeRange(offset, masternodePublicKeySize)];
    offset += masternodePublicKeySize;
    //Message Signature
    if (length - offset < 1) return nil;
    uint8_t messageSignatureSize = [message UInt8AtOffset:offset];
    offset += 1;
    if (length - offset < messageSignatureSize) return nil;
    NSData * messageSignature = [message subdataWithRange:NSMakeRange(offset, messageSignatureSize)];
    offset+= messageSignatureSize;
    if (length - offset < 8) return nil;
    NSData * timestampData = [message subdataWithRange:NSMakeRange(offset, 8)];
    uint64_t timestamp = [message UInt64AtOffset:offset];
    offset += 8;
    if (length - offset < 4) return nil;
    uint32_t protocolVersion = [message UInt32AtOffset:offset];
    offset += 4;
    
    UInt256 masternodeBroadcastHash = [DSMasternodeBroadcast hashWithUTXO:masternodeUTXO collateralPublicKey:collateralPublicKey timeStampData:timestampData];
    
    
    DSMasternodeBroadcast * broadcast = [[DSMasternodeBroadcast alloc] initWithUTXO:masternodeUTXO ipAddress:masternodeAddress port:port protocolVersion:protocolVersion publicKey:masternodePublicKey signature:messageSignature signatureTimestamp:timestamp masternodeBroadcastHash:masternodeBroadcastHash onChain:chain];
    
    NSData * restOfData = [message subdataWithRange:NSMakeRange(offset, length-offset)];
    DSMasternodePing * ping = [DSMasternodePing masternodePingFromMessage:restOfData];
    if (ping) broadcast.lastPing = ping;
    
    return broadcast;
}

-(NSString *)uniqueID {
    return [NSData dataWithUInt256:self.masternodeBroadcastHash].shortHexString;
}

-(DSMasternodeBroadcastEntity*)masternodeBroadcastEntity {
    NSArray * broadcastEntities = [DSMasternodeBroadcastEntity objectsMatching:@"masternodeBroadcastHash.masternodeBroadcastHash = %@",[NSData dataWithUInt256:self.masternodeBroadcastHash]];
    if ([broadcastEntities count]) {
        return [broadcastEntities objectAtIndex:0];
    }
    return nil;
}

@end
