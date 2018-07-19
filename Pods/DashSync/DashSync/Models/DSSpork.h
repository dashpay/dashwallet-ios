//
//  DSSpork.h
//  dashwallet
//
//  Created by Sam Westrich on 10/18/17.
//  Copyright © 2017 Aaron Voisine. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(uint32_t,DSSporkIdentifier) {
    DSSporkIdentifier_Spork2InstantSendEnabled = 10001,
    DSSporkIdentifier_Spork3InstantSendBlockFiltering = 10002,
    DSSporkIdentifier_Spork5InstantSendMaxValue = 10004,
    DSSporkIdentifier_Spork6NewSigs = 10005,
    DSSporkIdentifier_Spork8MasternodePaymentEnforcement = 10007,
    DSSporkIdentifier_Spork9SuperblocksEnabled = 10008,
    DSSporkIdentifier_Spork10MasternodePayUpdatedNodes = 10009,
    DSSporkIdentifier_Spork12ReconsiderBlocks = 10011,
    DSSporkIdentifier_Spork13OldSuperblockFlag = 10012,
    DSSporkIdentifier_Spork14RequireSentinelFlag = 10013,
    DSSporkIdentifier_Spork15DeterministicMasternodesEnabled = 10014
};

@class DSChain;

@interface DSSpork : NSObject

@property (nonatomic,assign,readonly) DSSporkIdentifier identifier;
@property (nonatomic,readonly) NSString* identifierString;
@property (nonatomic,assign,readonly,getter=isValid) BOOL valid;
@property (nonatomic,assign,readonly) uint64_t timeSigned;
@property (nonatomic,assign,readonly) uint64_t value;
@property (nonatomic,strong,readonly) NSData * signature;
@property (nonatomic,assign,readonly) UInt256 sporkHash;
@property (nonatomic,readonly) DSChain * chain;

+ (instancetype)sporkWithMessage:(NSData *)message onChain:(DSChain*)chain;
    
- (instancetype)initWithIdentifier:(DSSporkIdentifier)identifier value:(uint64_t)value timeSigned:(uint64_t)timeSigned signature:(NSData*)signature onChain:(DSChain*)chain;
    
-(BOOL)isEqualToSpork:(DSSpork*)spork;

@end
