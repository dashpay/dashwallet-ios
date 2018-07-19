//
//  DSCoinbaseTransaction.h
//  DashSync
//
//  Created by Sam Westrich on 7/12/18.
//

#import "DSTransaction.h"

@interface DSCoinbaseTransaction : DSTransaction

@property (nonatomic,assign) uint16_t coinbaseTransactionVersion;
@property (nonatomic,assign) uint32_t height;
@property (nonatomic,assign) UInt256 merkleRootMNList;

@end
