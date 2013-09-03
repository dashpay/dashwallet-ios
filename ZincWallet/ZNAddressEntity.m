//
//  ZNAddressEntity.m
//  ZincWallet
//
//  Created by Aaron Voisine on 8/26/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
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

#import "ZNAddressEntity.h"
#import "NSManagedObject+Utils.h"

@implementation ZNAddressEntity

@dynamic address;
@dynamic index;
@dynamic internal;
@dynamic newTx;
@dynamic txCount;

+ (instancetype)entityWithAddress:(NSString *)address index:(int32_t)index internal:(BOOL)internal
{
    ZNAddressEntity *e = [self managedObject];

    [e.managedObjectContext performBlockAndWait:^{
        e.address = address;
        e.index = index;
        e.internal = internal;
        e.newTx = NO;
        e.txCount = 0;
    }];
    
    return e;
}

// updates the appropriate entity from JSON, returns the updated entity or nil if no updates were made or on error
+ (instancetype)updateWithJSON:(NSDictionary *)JSON
{
    if (! [JSON isKindOfClass:[NSDictionary class]] || ! [JSON[@"address"] isKindOfClass:[NSString class]]) return nil;
    
    __block ZNAddressEntity *address = [self objectsMatching:@"address == %@", JSON[@"address"]].lastObject;
    
    if (! address) return nil;
    
    [[address managedObjectContext] performBlockAndWait:^{
        if ([JSON[@"n_tx"] isKindOfClass:[NSNumber class]] && [JSON[@"n_tx"] intValue] != address.txCount) {
            address.txCount = [JSON[@"n_tx"] intValue];
            address.newTx = YES;
        }
        else address = nil;
    }];
    
    return address;
}

@end
