//
//  DSPeerEntity+CoreDataProperties.h
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

#import "DSPeerEntity+CoreDataClass.h"

NS_ASSUME_NONNULL_BEGIN

@interface DSPeerEntity (CoreDataProperties)

+ (NSFetchRequest<DSPeerEntity *> *)fetchRequest;

@property (nonatomic) int32_t address;
@property (nonatomic) NSTimeInterval timestamp;
@property (nonatomic) NSTimeInterval lastRequestedMasternodeList;
@property (nonatomic) NSTimeInterval lastRequestedGovernanceSync;
@property (nonatomic) NSTimeInterval lowPreferenceTill;
@property (nonatomic) int16_t port;
@property (nonatomic) int64_t services;
@property (nonatomic) int16_t misbehavin;
@property (nonatomic) int32_t priority;
@property (nonatomic, retain) DSChainEntity *chain;

@end

NS_ASSUME_NONNULL_END
