//
//  DSMasternodePing.m
//  DashSync
//
//  Created by Sam Westrich on 5/31/18.
//

#import "DSMasternodePing.h"
#import "NSData+Bitcoin.h"

@interface DSMasternodePing()

@property (nonatomic,assign) DSUTXO utxo;
@property (nonatomic,assign) UInt256 chaintip;
@property (nonatomic,strong) NSData * signature;
@property (nonatomic,assign) NSTimeInterval signatureTimestamp;

@end

@implementation DSMasternodePing

-(instancetype)initWithUTXO:(DSUTXO)utxo chainTip:(UInt256)chainTip signature:(NSData*)signature signatureTimestamp:(NSTimeInterval)signatureTimestamp {
    if (!(self = [super init])) return nil;
    _utxo = utxo;
    _chaintip = chainTip;
    _signature = signature;
    _signatureTimestamp = signatureTimestamp;
    
    return self;
}

-(instancetype)initWithUTXO:(DSUTXO)utxo chainTip:(UInt256)chainTip signature:(NSData*)signature signatureTimestamp:(NSTimeInterval)signatureTimestamp packetSize:(uint64_t)packetSize {
    if (!(self = [self initWithUTXO:utxo chainTip:chainTip signature:signature signatureTimestamp:signatureTimestamp])) return nil;
    _packetSize = packetSize;
    
    return self;
}

+(DSMasternodePing*)masternodePingFromMessage:(NSData *)message {
    NSUInteger length = message.length;
    DSUTXO masternodePingUTXO;
    NSUInteger offset = 0;
    if (length - offset < 32) return nil;
    masternodePingUTXO.hash = [message UInt256AtOffset:offset];
    offset += 32;
    if (length - offset < 4) return nil;
    masternodePingUTXO.n = [message UInt32AtOffset:offset];
    offset += 4;
    if (length - offset < 1) return nil;
    uint8_t pingSigscriptSize = [message UInt8AtOffset:offset];
    offset += 1;
    //NSData * pingSigscript = [message subdataWithRange:NSMakeRange(offset, pingSigscriptSize)];
    offset += pingSigscriptSize;
    //uint32_t pingSequenceNumber = [message UInt32AtOffset:offset];
    offset += 4;
    if (length - offset < 32) return nil;
    UInt256 pingChaintip = [message UInt256AtOffset:offset];
    offset += 32;
    if (length - offset < 8) return nil;
    uint64_t timestamp = [message UInt64AtOffset:offset];
    offset += 8;
    
    //Message Signature
    if (length - offset < 1) return nil;
    uint8_t messageSignatureSize = [message UInt8AtOffset:offset];
    offset += 1;
    if (length - offset < messageSignatureSize) return nil;
    NSData * messageSignature = [message subdataWithRange:NSMakeRange(offset, messageSignatureSize)];
    offset+= messageSignatureSize;
    
    return [[DSMasternodePing alloc] initWithUTXO:masternodePingUTXO chainTip:pingChaintip signature:messageSignature signatureTimestamp:timestamp packetSize:offset];
}

@end
