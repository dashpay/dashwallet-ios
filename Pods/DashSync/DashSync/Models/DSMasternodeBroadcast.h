//
//  DSMasternodeBroadcast.h
//  DashSync
//
//  Created by Sam Westrich on 5/31/18.
//

#import <Foundation/Foundation.h>
#import "DSChain.h"
#import "IntTypes.h"

@class DSMasternodePing,DSMasternodeBroadcastEntity;

@interface DSMasternodeBroadcast : NSObject

@property (nonatomic,readonly) DSUTXO utxo;
@property (nonatomic,readonly) NSData * signature;
@property (nonatomic,readonly) NSTimeInterval signatureTimestamp;
@property (nonatomic,strong) DSMasternodePing * lastPing;
@property (nonatomic,readonly) UInt128 ipAddress;
@property (nonatomic,readonly) uint16_t port;
@property (nonatomic,readonly) uint32_t protocolVersion;
@property (nonatomic,readonly) NSData * publicKey;
@property (nonatomic,readonly) UInt256 masternodeBroadcastHash;
@property (nonatomic,readonly) DSChain * chain;

+(DSMasternodeBroadcast* _Nullable)masternodeBroadcastFromMessage:(NSData * _Nonnull)message onChain:(DSChain* _Nonnull)chain;
-(instancetype)initWithUTXO:(DSUTXO)utxo ipAddress:(UInt128)ipAddress port:(uint16_t)port protocolVersion:(uint32_t)protocolVersion publicKey:(NSData* _Nonnull)publicKey signature:(NSData* _Nonnull)signature signatureTimestamp:(NSTimeInterval)signatureTimestamp masternodeBroadcastHash:(UInt256)masternodeBroadcastHash onChain:(DSChain* _Nonnull)chain;
-(NSString * _Nonnull)uniqueID;
-(DSMasternodeBroadcastEntity*)masternodeBroadcastEntity;


@end
