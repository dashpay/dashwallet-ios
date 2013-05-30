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

#pragma mark - testElectrumSequence

- (void)testElectrumSequenceStretchKey
{
    ZNElectrumSequence *seq = [[ZNElectrumSequence alloc] init];    
    NSData *sk = [(id)seq performSelector:@selector(stretchKey:)
                  withObject:[NSData dataWithBytes:"\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0" length:16]];

    NSLog(@"0x00000000000000000000000000000000 stretched = 0x%@", [sk toHex]);
    
    STAssertEqualObjects(sk, [NSData dataWithHex:@"7e6003c97739f6c7791837e27b06526d7e16539b6400bcac805fb0b93477c85c"],
                         @"[ZNElectrumSequence stretchKey:]");
}

- (void)testElectrumSequenceMasterPublicKeyFromSeed
{
    ZNElectrumSequence *seq = [[ZNElectrumSequence alloc] init];    
    NSData *mpk = [seq masterPublicKeyFromSeed:[NSData dataWithBytes:"\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0" length:16]];
    
    NSLog(@"mpk from 0x00000000000000000000000000000000 = 0x%@", [mpk toHex]);
    
    STAssertEqualObjects(mpk, [NSData dataWithHex:@"c0e5ac2152df671bf21cb5c11593a7220c21c6cf4f7f43f08b2a9ea1ba6994f2"
                                                   "dccc1def89c7221751d3451ee9db222ad281f956979705904ecd9355f7c896df"],
                         @"[ZNElectrumSequence masterPublicKeyFromSeed:]");
}

- (void)testElectrumSequencePublicKey
{
    ZNElectrumSequence *seq = [[ZNElectrumSequence alloc] init];
    NSData *mpk = [seq masterPublicKeyFromSeed:[NSData dataWithBytes:"\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0" length:16]];
    NSData *pk = [seq publicKey:0 forChange:NO masterPublicKey:mpk];
    
    NSLog(@"publicKey:0 = %@", [pk toHex]);
    
    STAssertEqualObjects(pk, [NSData dataWithHex:@"04f1df504ca89c7be051cc175c156689fa8c4be2025490a7fcad05568e5b6861df"
                                                  "63e949d0d448d8c64571205c61918d1378771151d0d8e3682453d69dcdfdddc7"],
                         @"[ZNElecturmSequence publicKey:forChange:masterPublicKey:]");
}

- (void)testElectrumSequencePrivateKey
{
    ZNElectrumSequence *seq = [[ZNElectrumSequence alloc] init];
    NSString *privkey = [seq privateKey:0 forChange:NO
                         fromSeed:[NSData dataWithBytes:"\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0" length:16]];
    
    NSLog(@"privateKey:0 = %@", privkey);
    
    STAssertEqualObjects(privkey, @"5JB9HJXr1rCL6huhCcJKGAc38Q9eje9fiDiTiZK79YdQZfKPeXh",
                         @"[ZNElecturmSequence privateKey:forChange:fromSeed:]");
    
    //XXX need to add a test where the first byte of private key (after the 0x80 prefix) is zero
}

@end
