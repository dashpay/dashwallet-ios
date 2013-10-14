//
//  ZNPeerEntity.m
//  ZincWallet
//
//  Created by Aaron Voisine on 10/6/13.
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

#import "ZNPeerEntity.h"
#import "NSManagedObject+Utils.h"
#import <arpa/inet.h>

@implementation ZNPeerEntity

@dynamic address;
@dynamic timestamp;
@dynamic port;
@dynamic services;

+ (instancetype)createOrUpdateWithAddress:(int32_t)address port:(int16_t)port timestamp:(NSTimeInterval)timestamp
services:(int64_t)services
{
    ZNPeerEntity *e = [self objectsMatching:@"address == %u && port == %u", address, port].lastObject;
    
    if (! e) e = [ZNPeerEntity managedObject];

    [e.managedObjectContext performBlockAndWait:^{
        e.address = address;
        e.port = port;
        if (timestamp > e.timestamp) e.timestamp = timestamp;
        e.services = services;
    }];

    return e;
}

+ (NSArray *)createOrUpdateWithAddresses:(NSArray *)addresses ports:(NSArray *)ports timestamps:(NSArray *)timestamps
services:(NSArray *)services
{
    if (addresses.count > 100) { // break into chunks of 100 so we don't freeze the UI
        return [[self createOrUpdateWithAddresses:[addresses subarrayWithRange:NSMakeRange(0, 100)]
                 ports:[ports subarrayWithRange:NSMakeRange(0, 100)]
                 timestamps:[timestamps subarrayWithRange:NSMakeRange(0, 100)]
                 services:[services subarrayWithRange:NSMakeRange(0, 100)]] arrayByAddingObjectsFromArray:[self
                createOrUpdateWithAddresses:[addresses subarrayWithRange:NSMakeRange(100, addresses.count - 100)]
                ports:[ports subarrayWithRange:NSMakeRange(100, ports.count - 100)]
                timestamps:[timestamps subarrayWithRange:NSMakeRange(100, timestamps.count - 100)]
                services:[services subarrayWithRange:NSMakeRange(100, services.count - 100)]]];
    }

    NSMutableArray *a = [NSMutableArray arrayWithCapacity:addresses.count];
    NSMutableIndexSet *set = [NSMutableIndexSet indexSet];
    NSArray *peers = [self objectsMatching:@"address IN %@", addresses];
    
    [[NSManagedObject context] performBlockAndWait:^{
        [peers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            ZNPeerEntity *e = obj;
            NSUInteger i = [addresses indexOfObject:@(e.address)];
            
            while (i < addresses.count - 1 && ! [ports[i] isEqual:@(e.port)]) {
                i = [addresses indexOfObject:@(e.address) inRange:NSMakeRange(i + 1, addresses.count - (i + 1))];
            }
            
            if (i < ports.count && [ports[i] isEqual:@(e.port)]) {
                if ([timestamps[i] doubleValue] > e.timestamp) e.timestamp = [timestamps[i] doubleValue];
                e.services = [services[i] longLongValue];
                [a addObject:e];
                [set addIndex:i];
            }
        }];
    }];
    
    addresses = [NSMutableArray arrayWithArray:addresses];
    [(id)addresses removeObjectsAtIndexes:set];
    ports = [NSMutableArray arrayWithArray:ports];
    [(id)ports removeObjectsAtIndexes:set];
    timestamps = [NSMutableArray arrayWithArray:timestamps];
    [(id)timestamps removeObjectsAtIndexes:set];
    services = [NSMutableArray arrayWithArray:services];
    [(id)services removeObjectsAtIndexes:set];
    peers = [self managedObjectArrayWithLength:addresses.count];
    
    [[NSManagedObject context] performBlockAndWait:^{
        [peers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            ZNPeerEntity *e = obj;
        
            e.address = [addresses[idx] intValue];
            e.port = [ports[idx] shortValue];
            e.timestamp = [timestamps[idx] doubleValue];
            e.services = [services[idx] longLongValue];
            [a addObject:obj];
        }];
    }];
    
    return a;
}

@end
