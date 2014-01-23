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

- (instancetype)setAttributesFromPeer:(ZNPeer *)peer
{
    [[self managedObjectContext] performBlockAndWait:^{
        self.address = peer.address;
        self.port = peer.port;
        self.timestamp = peer.timestamp;
        self.services = peer.services;
        self.misbehavin = peer.misbehavin;
    }];

    return self;
}

- (ZNPeer *)peer
{
    __block ZNPeer *peer = nil;

    [[self managedObjectContext] performBlockAndWait:^{
        peer = [ZNPeer peerWithAddress:self.address port:self.port timestamp:self.timestamp services:self.services];
        peer.misbehavin = self.misbehavin;
    }];

    return peer;
}

@end
