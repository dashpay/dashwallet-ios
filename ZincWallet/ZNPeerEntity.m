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
#import "ZNPeer.h"
#import "NSManagedObject+Utils.h"
#import <arpa/inet.h>

@implementation ZNPeerEntity

@dynamic address;
@dynamic timestamp;
@dynamic port;
@dynamic services;
@dynamic misbehavin;

+ (instancetype)createOrUpdateWithPeer:(ZNPeer *)peer
{
    __block ZNPeerEntity *e = nil;

    [[self context] performBlockAndWait:^{
        e = [self objectsMatching:@"address == %d && port == %d", (int32_t)peer.address, (int16_t)peer.port].lastObject;
    
        if (! e) e = [ZNPeerEntity managedObject];

        e.address = peer.address;
        e.port = peer.port;
        if (peer.timestamp > e.timestamp) e.timestamp = peer.timestamp;
        e.services = peer.services;
    }];

    return e;
}

// more efficient method for creating or updating a lot of peer entities at once
+ (NSArray *)createOrUpdateWithPeers:(NSArray *)peers
{
    NSMutableArray *a = [NSMutableArray arrayWithCapacity:peers.count];
    
    [[self context] performBlockAndWait:^{
        NSMutableIndexSet *set = [NSMutableIndexSet indexSet];
        NSMutableArray *addresses = [NSMutableArray array];
        
        for (ZNPeer *p in peers) {
            [addresses addObject:@(p.address)];
        }
        
        NSArray *entities = [self objectsMatching:@"address in %@", addresses];
        
        for (ZNPeerEntity *e in entities) {
            NSUInteger i = [addresses indexOfObject:@(e.address)];
            
            while (i < addresses.count - 1 && [(ZNPeer *)peers[i] port] != e.port) {
                i = [addresses indexOfObject:@(e.address) inRange:NSMakeRange(i + 1, addresses.count - (i + 1))];
            }
            
            if (i < peers.count && [(ZNPeer *)peers[i] port] == e.port) {
                ZNPeer *p = peers[i];

                if (p.timestamp > e.timestamp) e.timestamp = p.timestamp;
                e.services = p.services;
                [a addObject:e];
                [set addIndex:i];
            }
        }
    
        NSMutableArray *prs = [NSMutableArray arrayWithArray:peers];
        NSUInteger idx = 0;

        [prs removeObjectsAtIndexes:set];
        entities = [self managedObjectArrayWithLength:prs.count];
        
        for (ZNPeerEntity *e in entities) {
            ZNPeer *p = prs[idx];
            
            e.address = p.address;
            e.port = p.port;
            e.timestamp = p.timestamp;
            e.services = p.services;
            [a addObject:e];
            idx++;
        }
    }];

#if DEBUG
    static int count = 0;
    
    count += a.count;
    NSLog(@"created or updated %d peers", count);
#endif

    return a;
}

@end
