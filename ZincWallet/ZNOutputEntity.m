//
//  ZNOutputEntity.m
//  ZincWallet
//
//  Created by Aaron Voisine on 8/22/13.
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

#import "ZNOutputEntity.h"
#import "NSManagedObject+Utils.h"

@implementation ZNOutputEntity

@dynamic address;
@dynamic n;
@dynamic txIndex;
@dynamic value;

+ (instancetype)entityWithJSON:(NSDictionary *)JSON
{
    if (! [JSON isKindOfClass:[NSDictionary class]]) return nil;

    return [[self managedObject] setAttributesFromJSON:JSON];
}

- (instancetype)setAttributesFromJSON:(NSDictionary *)JSON
{
    if (! [JSON isKindOfClass:[NSDictionary class]]) return self;
 
    [[self managedObjectContext] performBlockAndWait:^{
        if ([JSON[@"addr"] isKindOfClass:[NSString class]]) self.address = [NSString stringWithString:JSON[@"addr"]];
        if ([JSON[@"n"] isKindOfClass:[NSNumber class]]) self.n = [JSON[@"n"] intValue];
        if ([JSON[@"tx_index"] isKindOfClass:[NSNumber class]]) self.txIndex = [JSON[@"tx_index"] longLongValue];
        if ([JSON[@"value"] isKindOfClass:[NSNumber class]]) self.value = [JSON[@"value"] longLongValue];
    }];
    
    return self;
}

- (instancetype)setAddress:(NSString *)address txIndex:(int64_t)txIndex n:(int32_t)n value:(int64_t)value
{
    [[self managedObjectContext] performBlockAndWait:^{
        if (address.length) self.address = address;
        if (txIndex > 0) self.txIndex = txIndex;
        if (n >= 0 && n != NSNotFound) self.n = n;
        if (value > 0) self.value = value;
    }];
    
    return self;
}

@end
