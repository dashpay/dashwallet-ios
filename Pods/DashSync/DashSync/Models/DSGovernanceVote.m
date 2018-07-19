//
//  DSGovernanceObjectVote.m
//  DashSync
//
//  Created by Sam Westrich on 6/12/18.
//

#import "DSGovernanceVote.h"
#import "NSData+Bitcoin.h"
#import "NSData+Dash.h"
#import "DSChain.h"
#import "DSKey.h"
#import "NSData+Bitcoin.h"
#import "NSMutableData+Dash.h"
#import "DSMasternodeManager.h"
#import "DSChainManager.h"
#import "DSChainPeerManager.h"
#import "DSMasternodeBroadcast.h"
#import "DSMasternodeBroadcastEntity+CoreDataClass.h"
#import "NSManagedObject+Sugar.h"

@interface DSGovernanceVote()

@property (nonatomic,strong) DSMasternodeBroadcast * masternodeBroadcast;
@property (nonatomic,assign) DSGovernanceVoteOutcome outcome;
@property (nonatomic,assign) DSGovernanceVoteSignal signal;
@property (nonatomic,assign) NSTimeInterval createdAt;
@property (nonatomic,strong) DSChain * chain;
@property (nonatomic,assign) UInt256 parentHash;
@property (nonatomic,assign) UInt256 governanceVoteHash;
@property (nonatomic,strong) NSData * signature;
@property (nonatomic,assign) DSUTXO masternodeUTXO;

@end

@implementation DSGovernanceVote

// From the reference
//uint256 GetHash() const
//{
//    CHashWriter ss(SER_GETHASH, PROTOCOL_VERSION);
//    ss << vinMasternode;
//    ss << nParentHash;
//    ss << nVoteSignal;
//    ss << nVoteOutcome;
//    ss << nTime;
//    return ss.GetHash();
//}

+(UInt256)hashWithParentHash:(UInt256)parentHash voteCreationTimestamp:(uint64_t)voteCreationTimestamp voteSignal:(uint32_t)voteSignal voteOutcome:(uint32_t)voteOutcome masternodeUTXO:(DSUTXO)masternodeUTXO {
    //hash calculation
    NSMutableData * hashImportantData = [NSMutableData data];
    
    uint32_t index = (uint32_t)masternodeUTXO.n;
    [hashImportantData appendData:[NSData dataWithUInt256:masternodeUTXO.hash]];
    [hashImportantData appendBytes:&index length:4];
    uint8_t emptyByte = 0;
    uint32_t fullBits = UINT32_MAX;
    [hashImportantData appendBytes:&emptyByte length:1];
    [hashImportantData appendBytes:&fullBits length:4];
    [hashImportantData appendBytes:&parentHash length:32];
    [hashImportantData appendBytes:&voteSignal length:4];
    [hashImportantData appendBytes:&voteOutcome length:4];
    [hashImportantData appendBytes:&voteCreationTimestamp length:8];
    
    return hashImportantData.SHA256_2;
}

-(NSData*)dataMessage {
    NSMutableData * data = [NSMutableData data];
    [data appendUInt256:self.masternodeUTXO.hash];
    [data appendUInt32:(uint32_t)self.masternodeUTXO.n];
    if (self.chain.protocolVersion < 70209) { //switch to outpoint in 70209
        [data appendUInt8:0];
        [data appendUInt32:UINT32_MAX];
    }
    [data appendUInt256:self.parentHash];
    [data appendUInt32:self.outcome];
    [data appendUInt32:self.signal];
    [data appendUInt64:self.createdAt];
    [data appendVarInt:self.signature.length];
    [data appendData:self.signature];
    return [data copy];
}

+(DSGovernanceVote* _Nullable)governanceVoteFromMessage:(NSData * _Nonnull)message onChain:(DSChain* _Nonnull)chain {
    NSUInteger length = message.length;
    NSUInteger offset = 0;
    
    DSUTXO masternodeUTXO;
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
        if (length - offset < sigscriptSize) return nil;
        //NSData * sigscript = [message subdataWithRange:NSMakeRange(offset, sigscriptSize)];
        offset += sigscriptSize;
        if (length - offset < 4) return nil;
        //uint32_t sequenceNumber = [message UInt32AtOffset:offset];
        offset += 4;
    }
    
    if (length - offset < 32) return nil;
    UInt256 parentHash = [message UInt256AtOffset:offset];
    offset += 32;
    if (length - offset < 4) return nil;
    uint32_t voteOutcome = [message UInt32AtOffset:offset];
    offset += 4;
    if (length - offset < 4) return nil;
    uint32_t voteSignal = [message UInt32AtOffset:offset];
    offset += 4;
    if (length - offset < 4) return nil;
    uint64_t voteCreationTimestamp = [message UInt64AtOffset:offset];
    offset += 8;
    
    if (length - offset < 1) return nil;
    uint8_t messageSignatureSize = [message UInt8AtOffset:offset];
    offset += 1;
    if (length - offset < messageSignatureSize) return nil;
    NSData * messageSignature = [message subdataWithRange:NSMakeRange(offset, messageSignatureSize)];
    offset+= messageSignatureSize;
    
    DSGovernanceVote * governanceVote = [[DSGovernanceVote alloc] initWithParentHash:parentHash forMasternodeUTXO:masternodeUTXO voteOutcome:voteOutcome voteSignal:voteSignal createdAt:voteCreationTimestamp signature:messageSignature onChain:chain];
    return governanceVote;
    
}

-(instancetype)initWithParentHash:(UInt256)parentHash forMasternodeUTXO:(DSUTXO)masternodeUTXO voteOutcome:(DSGovernanceVoteOutcome)voteOutcome voteSignal:(DSGovernanceVoteSignal)voteSignal createdAt:(NSTimeInterval)createdAt signature:(NSData*)signature onChain:(DSChain* _Nonnull)chain {
    if (!(self = [super init])) return nil;
    self.outcome = voteOutcome;
    self.signal = voteSignal;
    self.chain = chain;
    self.createdAt = createdAt;
    self.parentHash = parentHash;
    self.masternodeUTXO = masternodeUTXO;
    self.governanceVoteHash = [DSGovernanceVote hashWithParentHash:parentHash voteCreationTimestamp:createdAt voteSignal:voteSignal voteOutcome:voteOutcome masternodeUTXO:masternodeUTXO];
    self.signature = signature;
    return self;
}

-(DSMasternodeBroadcast *)masternodeBroadcast {
    if (_masternodeBroadcast) return _masternodeBroadcast;
    NSArray * masternodeBroadcasts = [DSMasternodeBroadcastEntity objectsMatching:@"utxoHash = %@ && utxoIndex = %@",[NSData dataWithUInt256:(UInt256)self.masternodeUTXO.hash],@(self.masternodeUTXO.n)];
    if ([masternodeBroadcasts count]) {
        DSMasternodeBroadcastEntity * masternodeBroadcastEntity = [masternodeBroadcasts firstObject];
        return [masternodeBroadcastEntity masternodeBroadcast];
    }
    return nil;
}

-(void)signWithKey:(DSKey*)key {
    self.signature = [key sign:self.governanceVoteHash];
}

-(BOOL)isValid {
    if (uint256_is_zero(self.masternodeUTXO.hash)) return FALSE;
    if (!self.createdAt) return FALSE;
    if (uint256_is_zero(self.parentHash)) return FALSE;
    DSChainPeerManager * peerManager = [[DSChainManager sharedInstance] peerManagerForChain:self.chain];
    DSMasternodeBroadcast * masternodeBroacast = [peerManager.masternodeManager masternodeBroadcastForUTXO:self.masternodeUTXO];
    DSKey * key = [DSKey keyWithPublicKey:masternodeBroacast.publicKey];
    BOOL isValid = [key verify:self.governanceVoteHash signature:self.signature];
    return isValid;
}

@end
