//
//  ZincWalletTests.m
//  ZincWalletTests
//
//  Created by Aaron Voisine on 5/8/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZincWalletTests.h"

#import "ZNWallet.h"
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

#pragma mark - testWallet

- (void)testWalletDecodePhrase
{
    NSData *d = [[ZNWallet sharedInstance] performSelector:@selector(decodePhrase:)
                 withObject:@"like just love know never want time out there make look eye"];
    
    NSLog(@"like just love know never want time out there make look eye = 0x%@", [d toHex]);
    
    STAssertEqualObjects(d, [@"00285dfe00285e0100285e0400285e07" dataUsingEncoding:NSUTF8StringEncoding],
                         @"[ZNWallet decodePhrase:]");
    
    d = [[ZNWallet sharedInstance] performSelector:@selector(decodePhrase:)
         withObject:@"kick chair mask master passion quick raise smooth unless wander actually broke"];
    
    NSLog(@"kick chair mask master passion quick raise smooth unless wander actually broke = 0x%@", [d toHex]);
    
    STAssertEqualObjects(d, [@"fea983ac0028608e0028609100286094" dataUsingEncoding:NSUTF8StringEncoding],
                         @"[ZNWallet decodePhrase:]");
    
    d = [[ZNWallet sharedInstance] performSelector:@selector(decodePhrase:)
         withObject:@"kick quiet student ignore cruel danger describe accident eager darkness embrace suppose"];
    
    NSLog(@"kick quiet student ignore cruel danger describe accident eager darkness embrace suppose = 0x%@", [d toHex]);
    
    STAssertEqualObjects(d, [@"8d02be487e1953ce2dd6c186fcc97e65" dataUsingEncoding:NSUTF8StringEncoding],
                         @"[ZNWallet decodePhrase:]");
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
