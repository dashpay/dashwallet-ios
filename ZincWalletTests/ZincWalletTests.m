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
#import "ZNTransaction.h"
#import "ZNKey.h"
#import "NSData+Hash.h"
#import "NSString+Base58.h"

@implementation ZincWalletTests

//XXX remember to test on iOS 5

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

// XXX
// standard free transaction no change
// standard free transaction with change
// transaction with an output below 0.01
// transaction with change below 0.01
// transaction over 10k
// free transaction who's inputs are too new to hit min free priority
// transaction with change below min allowable output

#pragma mark - testTransaction

- (void)testTransactionHeightUntilFree
{
    NSData *hash = [NSMutableData dataWithLength:32], *script = [NSMutableData dataWithLength:136];
    NSString *addr = @"1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa";
    ZNTransaction *tx = [[ZNTransaction alloc] initWithInputHashes:@[hash] inputIndexes:@[@0] inputScripts:@[script]
                         outputAddresses:@[addr, addr] outputAmounts:@[@100000000, @4900000000]];
    
    NSUInteger height = [tx blockHeightUntilFreeForAmounts:@[@5000000000] withBlockHeights:@[@1]];
    uint64_t priority = [tx priorityForAmounts:@[@5000000000] withAges:@[@(height - 1)]];
    
    NSLog(@"height = %d", height);
    NSLog(@"priority = %llu", priority);
    
    STAssertTrue(priority >= TX_FREE_MIN_PRIORITY, @"[ZNTransaction heightUntilFreeFor:atHeights:]");

    tx = [[ZNTransaction alloc] initWithInputHashes:@[hash, hash, hash, hash, hash, hash, hash, hash, hash, hash]
          inputIndexes:@[@0, @0,@0, @0, @0, @0, @0, @0, @0, @0]
          inputScripts:@[script, script, script, script, script, script, script, script, script, script]
          outputAddresses:@[addr, addr, addr, addr, addr, addr, addr, addr, addr, addr]
          outputAmounts:@[@1000000, @1000000, @1000000, @1000000, @1000000, @1000000, @1000000, @1000000, @1000000,
                             @1000000]];
    
    height = [tx blockHeightUntilFreeForAmounts:@[@1000000, @1000000, @1000000, @1000000, @1000000, @1000000, @1000000,
                                                  @1000000, @1000000, @1000000]
              withBlockHeights:@[@1, @2, @3, @4, @5, @6, @7, @8, @9, @10]];
    priority = [tx priorityForAmounts:@[@1000000, @1000000, @1000000, @1000000, @1000000, @1000000, @1000000, @1000000,
                                        @1000000, @1000000]
                withAges:@[@(height - 1), @(height - 2), @(height - 3), @(height - 4), @(height - 5), @(height - 6),
                           @(height - 7), @(height - 8), @(height - 9), @(height - 10)]];
    
    NSLog(@"height = %d", height);
    NSLog(@"priority = %llu", priority);
    
    STAssertTrue(priority >= TX_FREE_MIN_PRIORITY, @"[ZNTransaction heightUntilFreeFor:atHeights:]");
}

#pragma mark - testWallet

- (void)testWalletDecodePhrase
{
    NSData *d = [[ZNWallet sharedInstance] performSelector:@selector(decodePhrase:)
                 withObject:@"like just love know never want time out there make look eye"];
    
    NSLog(@"like just love know never want time out there make look eye = 0x%@", [d toHex]);
    
    STAssertEqualObjects(d, [NSData dataWithHex:@"00285dfe00285e0100285e0400285e07"], @"[ZNWallet decodePhrase:]");
    
    d = [[ZNWallet sharedInstance] performSelector:@selector(decodePhrase:)
         withObject:@"kick chair mask master passion quick raise smooth unless wander actually broke"];
    
    NSLog(@"kick chair mask master passion quick raise smooth unless wander actually broke = 0x%@", [d toHex]);
    
    STAssertEqualObjects(d, [NSData dataWithHex:@"fea983ac0028608e0028609100286094"], @"[ZNWallet decodePhrase:]");
    
    d = [[ZNWallet sharedInstance] performSelector:@selector(decodePhrase:)
         withObject:@"kick quiet student ignore cruel danger describe accident eager darkness embrace suppose"];
    
    NSLog(@"kick quiet student ignore cruel danger describe accident eager darkness embrace suppose = 0x%@", [d toHex]);
    
    STAssertEqualObjects(d, [NSData dataWithHex:@"8d02be487e1953ce2dd6c186fcc97e65"], @"[ZNWallet decodePhrase:]");
}

- (void)testWalletEncodePhrase
{
    NSString *s = [[ZNWallet sharedInstance] performSelector:@selector(encodePhrase:)
                   withObject:[NSData dataWithHex:@"00285dfe00285e0100285e0400285e07"]];
    
    NSLog(@"0x00285dfe00285e0100285e0400285e07 = %@", s);
    
    STAssertEqualObjects(s, @"like just love know never want time out there make look eye",
                         @"[ZNWallet encodePhrase:]");
    
    s = [[ZNWallet sharedInstance] performSelector:@selector(encodePhrase:)
         withObject:[NSData dataWithHex:@"00000000000000000000000000000000"]];

    NSLog(@"0x00285dfe00285e0100285e0400285e07 = %@", s);
    
    s = [[ZNWallet sharedInstance] performSelector:@selector(encodePhrase:)
         withObject:[NSData dataWithHex:@"fea983ac0028608e0028609100286094"]];
    
    NSLog(@"0x00285dfe00285e0100285e0400285e07 = %@", s);
    
    STAssertEqualObjects(s, @"kick chair mask master passion quick raise smooth unless wander actually broke",
                         @"[ZNWallet encodePhrase:]");
    
    s = [[ZNWallet sharedInstance] performSelector:@selector(encodePhrase:)
         withObject:[NSData dataWithHex:@"8d02be487e1953ce2dd6c186fcc97e65"]];
    
    NSLog(@"0x8d02be487e1953ce2dd6c186fcc97e65 = %@", s);
    
    STAssertEqualObjects(s, @"kick quiet student ignore cruel danger describe accident eager darkness embrace suppose",
                         @"[ZNWallet encodePhrase:]");    
}

#pragma mark - testElectrumSequence

- (void)testElectrumSequenceStretchKey
{
    ZNElectrumSequence *seq = [ZNElectrumSequence new];
    NSData *sk = [(id)seq performSelector:@selector(stretchKey:)
                  withObject:[@"00000000000000000000000000000000" dataUsingEncoding:NSUTF8StringEncoding]];

    NSLog(@"0x00000000000000000000000000000000 stretched = 0x%@", [sk toHex]);
    
    STAssertEqualObjects(sk, [NSData dataWithHex:@"7c2548ab89ffea8a6579931611969ffc0ed580ccf6048d4230762b981195abe5"],
                         @"[ZNElectrumSequence stretchKey:]");
}

- (void)testElectrumSequenceMasterPublicKeyFromSeed
{
    ZNElectrumSequence *seq = [ZNElectrumSequence new];
    NSData *mpk = [seq masterPublicKeyFromSeed:[@"00000000000000000000000000000000"
                                                dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSLog(@"mpk from 0x00000000000000000000000000000000 = 0x%@", [mpk toHex]);
    
    STAssertEqualObjects(mpk, [NSData dataWithHex:@"4e13b0f311a55b8a5db9a32e959da9f011b131019d4cebe6141b9e2c93edcbfc"
                                                   "0954c358b062a9f94111548e50bde5847a3096b8b7872dcffadb0e9579b9017b"],
                         @"[ZNElectrumSequence masterPublicKeyFromSeed:]");
}

- (void)testElectrumSequencePublicKey
{
    ZNElectrumSequence *seq = [ZNElectrumSequence new];
    NSData *mpk = [seq masterPublicKeyFromSeed:[@"00000000000000000000000000000000"
                                                dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *pk = [seq publicKey:0 forChange:NO masterPublicKey:mpk];
    NSString *addr = [(ZNKey *)[ZNKey keyWithPublicKey:pk] address];
    
    NSLog(@"publicKey:0 = %@", [pk toHex]);
    NSLog(@"addr:0 = %@", addr);
    
    STAssertEqualObjects(pk, [NSData dataWithHex:@"040900f07c15d3fa441979e71d7ccdcca1afc30a28de07a0525a3d7655dc49cca"
                                                  "0f844fb0903b3cccc4604107a9de6a0571c4a39996a9e4bd6ab596138ecae54f5"],
                         @"[ZNElecturmSequence publicKey:forChange:masterPublicKey:]");
    STAssertEqualObjects(addr, @"1FHsTashEBUNPQwC1CwVjnKUxzwgw73pU4", @"[[ZNKey keyWithPublicKey:] address]");
}

- (void)testElectrumSequencePrivateKey
{
    ZNElectrumSequence *seq = [ZNElectrumSequence new];
    NSString *privkey = [seq privateKey:0 forChange:NO
                         fromSeed:[@"00000000000000000000000000000000" dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSLog(@"privateKey:0 = %@", privkey);
    
    STAssertEqualObjects(privkey, @"5Khs7w6fBkogoj1v71Mdt4g8m5kaEyRaortmK56YckgTubgnrhz",
                         @"[ZNElecturmSequence privateKey:forChange:fromSeed:]");

    // this tests a private key that starts with 0x00
    privkey = [seq privateKey:64 forChange:NO
               fromSeed:[@"00000000000000000000000000000000" dataUsingEncoding:NSUTF8StringEncoding]];

    NSLog(@"privateKey:64 = %@ = 0x%@", privkey, [privkey base58checkToHex]);

    STAssertEqualObjects(privkey, @"5HpiKboFc3pPXwWND5SCjPjnojCLLv9i9nTp8HWEZqZsraKmkPu",
                         @"[ZNElecturmSequence privateKey:forChange:fromSeed:]");    
}

@end
