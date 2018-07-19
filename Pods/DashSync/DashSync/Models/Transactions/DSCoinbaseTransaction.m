//
//  DSCoinbaseTransaction.m
//  DashSync
//
//  Created by Sam Westrich on 7/12/18.
//

#import "DSCoinbaseTransaction.h"
#import "NSData+Bitcoin.h"

@implementation DSCoinbaseTransaction

- (instancetype)initWithMessage:(NSData *)message onChain:(DSChain *)chain
{
    if (! (self = [super initWithMessage:message onChain:chain])) return nil;
    NSUInteger length = message.length;
    uint32_t off = self.payloadOffset;
    if (length - off < 2) return nil;
    uint16_t version = [message UInt16AtOffset:off];
    off += 2;
    if (length - off < 4) return nil;
    uint32_t height = [message UInt32AtOffset:off];
    off += 4;
    if (length - off < 32) return nil;
    UInt256 merkleRootMNList = [message UInt256AtOffset:off];
    
    self.coinbaseTransactionVersion = version;
    self.height = height;
    self.merkleRootMNList = merkleRootMNList;

    return self;
}

@end
