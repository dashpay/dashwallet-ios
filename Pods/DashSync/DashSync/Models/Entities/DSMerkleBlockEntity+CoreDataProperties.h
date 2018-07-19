//
//  DSMerkleBlockEntity+CoreDataProperties.h
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

#import "DSMerkleBlockEntity+CoreDataClass.h"


NS_ASSUME_NONNULL_BEGIN

@interface DSMerkleBlockEntity (CoreDataProperties)

+ (NSFetchRequest<DSMerkleBlockEntity *> *)fetchRequest;

@property (nullable, nonatomic, retain) NSData *blockHash;
@property (nullable, nonatomic, retain) NSData *flags;
@property (nullable, nonatomic, retain) NSData *hashes;
@property (nonatomic, assign) int32_t height;
@property (nullable, nonatomic, retain) NSData *merkleRoot;
@property (nonatomic, assign) int32_t nonce;
@property (nullable, nonatomic, retain) NSData *prevBlock;
@property (nonatomic, assign) int32_t target;
@property (nonatomic, assign) NSTimeInterval timestamp;
@property (nonatomic, assign) int32_t totalTransactions;
@property (nonatomic, assign) int32_t version;
@property (nullable, nonatomic, retain) DSChainEntity *chain;

@end

NS_ASSUME_NONNULL_END
