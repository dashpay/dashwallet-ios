//
//  ZincWalletTests.m
//  ZincWalletTests
//
//  Created by Aaron Voisine on 5/8/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZincWalletTests.h"

#import "ZNElectrumSequence.h"
#import "NSData+Hash.h"

@implementation ZincWalletTests

- (void)setUp
{
    [super setUp];
    
    // Set-up code here.
}

- (void)tearDown
{
    // Tear-down code here.
    
    [super tearDown];
}

- (void)testElectrumSequenceStretchKey
{
    //STFail(@"Unit tests are not implemented yet in ZincWalletTests");
    
    ZNElectrumSequence *seq = [[ZNElectrumSequence alloc] init];
    
    NSData *q = [(id)seq performSelector:@selector(stretchKey:)
                 withObject:[NSData dataWithBytes:"\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0" length:16]];
    NSData *a = [NSData dataWithHex:@"7e6003c97739f6c7791837e27b06526d7e16539b6400bcac805fb0b93477c85c"];

    NSLog(@"0x00000000000000000000000000000000 stretched = 0x%@", [q toHex]);
    
    STAssertEqualObjects(q, a, @"[ZNElectrumSequence stretchKey:]");
}

- (void)testElectrumSequenceMasterPublicKeyFromSeed
{
    ZNElectrumSequence *seq = [[ZNElectrumSequence alloc] init];
    
    NSData *q = [seq masterPublicKeyFromSeed:[NSData dataWithBytes:"\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0" length:16]];
    NSData *a = [NSData dataWithHex:@"c0e5ac2152df671bf21cb5c11593a7220c21c6cf4f7f43f08b2a9ea1ba6994f2"
                                     "dccc1def89c7221751d3451ee9db222ad281f956979705904ecd9355f7c896df"];
    
    NSLog(@"mpk from 0x00000000000000000000000000000000 = 0x%@", [q toHex]);
    
    STAssertEqualObjects(q, a, @"[ZNElectrumSequence masterPublicKeyFromSeed:]");
}

- (void)testElectrumSequencePublicKey
{
    ZNElectrumSequence *seq = [[ZNElectrumSequence alloc] init];
    NSData *mpk = [seq masterPublicKeyFromSeed:[NSData dataWithBytes:"\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0" length:16]];

    NSData *q = [seq publicKey:0 forChange:NO masterPublicKey:mpk];
    NSData *a = [NSData dataWithHex:@"04f1df504ca89c7be051cc175c156689fa8c4be2025490a7fcad05568e5b6861df"
                                     "63e949d0d448d8c64571205c61918d1378771151d0d8e3682453d69dcdfdddc7"];
    
    NSLog(@"publicKey:0 = %@", [q toHex]);
    
    STAssertEqualObjects(q, a, @"[ZNElecturmSequence publicKey:forChange:masterPublicKey:]");
}

@end
