//
//  DSTxOutputEntity+CoreDataProperties.h
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

#import "DSTxOutputEntity+CoreDataClass.h"


NS_ASSUME_NONNULL_BEGIN

@interface DSTxOutputEntity (CoreDataProperties)

+ (NSFetchRequest<DSTxOutputEntity *> *)fetchRequest;

@property (nonatomic, retain) NSData *txHash;
@property (nonatomic) int32_t n;
@property (nonatomic, retain) NSString *address;
@property (nonatomic, retain) NSData *script;
@property (nonatomic, retain) NSString *shapeshiftOutboundAddress;
@property (nonatomic) int64_t value;
@property (nullable, nonatomic, retain) DSTxInputEntity * spentInInput;
@property (nonatomic, retain) DSTransactionEntity *transaction;
@property (nonatomic, retain) DSAddressEntity *localAddress;
@property (nonatomic, retain) DSAccountEntity *account;

@end

NS_ASSUME_NONNULL_END
