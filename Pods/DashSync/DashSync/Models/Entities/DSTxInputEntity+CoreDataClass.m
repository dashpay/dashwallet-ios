//
//  DSTxInputEntity+CoreDataClass.m
//  
//
//  Created by Sam Westrich on 5/20/18.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "DSTxInputEntity+CoreDataClass.h"
#import "DSTransactionEntity+CoreDataClass.h"
#import "DSTransaction.h"
#import "DSTxOutputEntity+CoreDataClass.h"
#import "NSData+Bitcoin.h"
#import "NSManagedObject+Sugar.h"

@implementation DSTxInputEntity

- (instancetype)setAttributesFromTx:(DSTransaction *)tx inputIndex:(NSUInteger)index forTransactionEntity:(DSTransactionEntity*)transactionEntity
{
    UInt256 hash = UINT256_ZERO;
    
    [tx.inputHashes[index] getValue:&hash];
    self.txHash = [NSData dataWithBytes:&hash length:sizeof(hash)];
    self.n = [tx.inputIndexes[index] intValue];
    self.signature = (tx.inputSignatures[index] != [NSNull null]) ? tx.inputSignatures[index] : nil;
    self.sequence = [tx.inputSequences[index] intValue];
    self.transaction = transactionEntity;
    DSTxOutputEntity * outputEntity = [DSTxOutputEntity objectsMatching:@"txHash == %@ && n == %d", self.txHash, self.n].lastObject;
    self.localAddress = outputEntity.localAddress;
    
    // mark previously unspent outputs as spent
    [outputEntity setSpentInInput:self];
    
    return self;
}


@end
