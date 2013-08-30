//
//  ZincWalletTests.m
//  ZincWalletTests
//
//  Created by Aaron Voisine on 5/8/13.
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

#import "ZincWalletTests.h"

#import "ZNWallet.h"
#import "ZNElectrumSequence.h"
#import "ZNBIP32Sequence.h"
#import "ZNElecturmMnemonic.h"
#import "ZNBIP39Mnemonic.h"
#import "ZNTransaction.h"
#import "ZNKey.h"
#import "NSData+Hash.h"
#import "NSString+Base58.h"

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

// XXX
// standard free transaction no change
// standard free transaction with change
// transaction with an output below 0.01
// transaction with change below 0.01
// transaction over 10k
// free transaction who's inputs are too new to hit min free priority
// transaction with change below min allowable output
// test gap limit with gaps in chain less than the limit

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

#pragma mark - testBIP39Mnemonic

//XXXX test bip39
//- (void)testBIP39MnemonicDecodePhrase
//{
//    id<ZNMnemonic> mnemonic = [ZNBIP39Mnemonic sharedInstance];
//    
//    NSData *d = [mnemonic decodePhrase:@"like just love know never want time out there make look eye"];
//    
//    NSLog(@"like just love know never want time out there make look eye = 0x%@", [NSString hexWithData:d]);
//    
//    //STAssertEqualObjects(d, @"00285dfe00285e0100285e0400285e07".hexToData, @"[ZNWallet decodePhrase:]");
//    
//    d = [mnemonic decodePhrase:@"kick chair mask master passion quick raise smooth unless wander actually broke"];
//    
//    NSLog(@"kick chair mask master passion quick raise smooth unless wander actually broke = 0x%@",
//          [NSString hexWithData:d]);
//    
//    //STAssertEqualObjects(d, @"fea983ac0028608e0028609100286094".hexToData, @"[ZNWallet decodePhrase:]");
//    
//    // test of phrase with trailing space
//    d = [mnemonic
//         decodePhrase:@"kick quiet student ignore cruel danger describe accident eager darkness embrace suppose "];
//    
//    NSLog(@"kick quiet student ignore cruel danger describe accident eager darkness embrace suppose = 0x%@",
//          [NSString hexWithData:d]);
//    
//    //STAssertEqualObjects(d, @"8d02be487e1953ce2dd6c186fcc97e65".hexToData, @"[ZNWallet decodePhrase:]");
//}

- (void)testBIP39MnemonicEncodePhrase
{
    id<ZNMnemonic> mnemonic = [ZNBIP39Mnemonic sharedInstance];
    
    NSString *s = [mnemonic encodePhrase:@"00285dfe00285e0100285e0400285e07".hexToData];
    
    NSLog(@"0x00285dfe00285e0100285e0400285e07 = %@", s);
    
    STAssertEqualObjects([mnemonic decodePhrase:s], @"00285dfe00285e0100285e0400285e07".hexToData,
                         @"[ZNWallet encodePhrase:]");
    
    s = [mnemonic encodePhrase:@"00000000000000000000000000000000".hexToData];
    
    NSLog(@"0x00000000000000000000000000000000 = %@", s);

    STAssertEqualObjects([mnemonic decodePhrase:s], @"00000000000000000000000000000000".hexToData,
                         @"[ZNWallet encodePhrase:]");
    
    s = [mnemonic encodePhrase:@"fea983ac0028608e0028609100286094".hexToData];
    
    NSLog(@"0xfea983ac0028608e0028609100286094 = %@", s);
    
    STAssertEqualObjects([mnemonic decodePhrase:s], @"fea983ac0028608e0028609100286094".hexToData,
                         @"[ZNWallet encodePhrase:]");
    
    s = [mnemonic encodePhrase:@"8d02be487e1953ce2dd6c186fcc97e65".hexToData];
    
    NSLog(@"0x8d02be487e1953ce2dd6c186fcc97e65 = %@", s);
    
    STAssertEqualObjects([mnemonic decodePhrase:s], @"8d02be487e1953ce2dd6c186fcc97e65".hexToData,
                         @"[ZNWallet encodePhrase:]");
}


#pragma mark - testElectrumMnemonic

- (void)testElectrumMnemonicDecodePhrase
{
    id<ZNMnemonic> mnemonic = [ZNElecturmMnemonic sharedInstance];

    NSData *d = [mnemonic decodePhrase:@"like just love know never want time out there make look eye"];

    NSLog(@"like just love know never want time out there make look eye = 0x%@", [NSString hexWithData:d]);
    
    STAssertEqualObjects(d, @"00285dfe00285e0100285e0400285e07".hexToData, @"[ZNWallet decodePhrase:]");
    
    d = [mnemonic decodePhrase:@"kick chair mask master passion quick raise smooth unless wander actually broke"];
    
    NSLog(@"kick chair mask master passion quick raise smooth unless wander actually broke = 0x%@",
          [NSString hexWithData:d]);
    
    STAssertEqualObjects(d, @"fea983ac0028608e0028609100286094".hexToData, @"[ZNWallet decodePhrase:]");
    
    // test of phrase with trailing space
    d = [mnemonic
         decodePhrase:@"kick quiet student ignore cruel danger describe accident eager darkness embrace suppose "];
    
    NSLog(@"kick quiet student ignore cruel danger describe accident eager darkness embrace suppose = 0x%@",
          [NSString hexWithData:d]);
    
    STAssertEqualObjects(d, @"8d02be487e1953ce2dd6c186fcc97e65".hexToData, @"[ZNWallet decodePhrase:]");
}

- (void)testElectrumMnemonicEncodePhrase
{
    id<ZNMnemonic> mnemonic = [ZNElecturmMnemonic sharedInstance];
    
    NSString *s = [mnemonic encodePhrase:@"00285dfe00285e0100285e0400285e07".hexToData];
    
    NSLog(@"0x00285dfe00285e0100285e0400285e07 = %@", s);
    
    STAssertEqualObjects(s, @"like just love know never want time out there make look eye",
                         @"[ZNWallet encodePhrase:]");
    
    s = [mnemonic encodePhrase:@"00000000000000000000000000000000".hexToData];

    NSLog(@"0x00285dfe00285e0100285e0400285e07 = %@", s);
    
    s = [mnemonic encodePhrase:@"fea983ac0028608e0028609100286094".hexToData];
    
    NSLog(@"0x00285dfe00285e0100285e0400285e07 = %@", s);
    
    STAssertEqualObjects(s, @"kick chair mask master passion quick raise smooth unless wander actually broke",
                         @"[ZNWallet encodePhrase:]");
    
    s = [mnemonic encodePhrase:@"8d02be487e1953ce2dd6c186fcc97e65".hexToData];
    
    NSLog(@"0x8d02be487e1953ce2dd6c186fcc97e65 = %@", s);
    
    STAssertEqualObjects(s, @"kick quiet student ignore cruel danger describe accident eager darkness embrace suppose",
                         @"[ZNWallet encodePhrase:]");    
}

#pragma mark - testBIP32Sequence

- (void)testBIP32SequencePrivateKey
{
    ZNBIP32Sequence *seq = [ZNBIP32Sequence new];
    NSData *seed = @"000102030405060708090a0b0c0d0e0f".hexToData;
    NSString *pk = [seq privateKey:2 | 0x80000000 internal:YES fromSeed:seed];
    NSData *d = [pk base58checkToData];

    NSLog(@"000102030405060708090a0b0c0d0e0f/0'/1/2' prv = %@", [NSString hexWithData:d]);

    STAssertEqualObjects(d, @"80cbce0d719ecf7431d88e6a89fa1483e02e35092af60c042b1df2ff59fa424dca01".hexToData,
                         @"[ZNBIP32Sequence privateKey:internal:fromSeed:]");

    // Test for correct zero padding of private keys, a *very* nasty potential bug
    pk = [seq privateKey:97 internal:NO fromSeed:seed];
    d = [pk base58checkToData];

    NSLog(@"000102030405060708090a0b0c0d0e0f/0'/0/97 prv = %@", [NSString hexWithData:d]);

    STAssertEqualObjects(d, @"8000136c1ad038f9a00871895322a487ed14f1cdc4d22ad351cfa1a0d235975dd701".hexToData,
                         @"[ZNBIP32Sequence privateKey:internal:fromSeed:]");
}

- (void)testBIP32SequenceMasterPublicKeyFromSeed
{
    ZNBIP32Sequence *seq = [ZNBIP32Sequence new];
    NSData *seed = @"000102030405060708090a0b0c0d0e0f".hexToData;
    NSData *mpk = [seq masterPublicKeyFromSeed:seed];
    
    NSLog(@"000102030405060708090a0b0c0d0e0f/0' pub+chain = %@", [NSString hexWithData:mpk]);
    
    STAssertEqualObjects(mpk, @"3442193e"
                               "47fdacbd0f1097043b78c63c20c34ef4ed9a111d980047ad16282c7ae6236141"
                               "035a784662a4a20a65bf6aab9ae98a6c068a81c52e4b032c0fb5400c706cfccc56".hexToData,
                         @"[ZNBIP32Sequence masterPublicKeyFromSeed:]");
}

- (void)testBIP32SequencePublicKey
{
    ZNBIP32Sequence *seq = [ZNBIP32Sequence new];
    NSData *seed = @"000102030405060708090a0b0c0d0e0f".hexToData;
    NSData *mpk = [seq masterPublicKeyFromSeed:seed];
    NSData *pub = [seq publicKey:0 internal:NO masterPublicKey:mpk];

    NSLog(@"000102030405060708090a0b0c0d0e0f/0'/0/0 pub = %@", [NSString hexWithData:pub]);
    
    //XXXX verify the value of pub using the output of some other implementation
}

- (void)testBIP32SequenceSerializedPrivateMasterFromSeed
{
    ZNBIP32Sequence *seq = [ZNBIP32Sequence new];
    NSData *seed = @"000102030405060708090a0b0c0d0e0f".hexToData;
    NSString *xprv = [seq serializedPrivateMasterFromSeed:seed];
    
    NSLog(@"000102030405060708090a0b0c0d0e0f xpriv = %@", xprv);
    
    STAssertEqualObjects(xprv,
     @"xprv9s21ZrQH143K3QTDL4LXw2F7HEK3wJUD2nW2nRk4stbPy6cq3jPPqjiChkVvvNKmPGJxWUtg6LnF5kejMRNNU3TGtRBeJgk33yuGBxrMPHi",
                         @"[ZNBIP32Sequence serializedPrivateMasterFromSeed:]");
}

- (void)testBIP32SequenceSerializedMasterPublicKey
{
    ZNBIP32Sequence *seq = [ZNBIP32Sequence new];
    NSData *seed = @"000102030405060708090a0b0c0d0e0f".hexToData;
    NSData *mpk = [seq masterPublicKeyFromSeed:seed];
    NSString *xpub = [seq serializedMasterPublicKey:mpk];
    
    NSLog(@"000102030405060708090a0b0c0d0e0f xpub = %@", xpub);
    
    STAssertEqualObjects(xpub,
     @"xpub68Gmy5EdvgibQVfPdqkBBCHxA5htiqg55crXYuXoQRKfDBFA1WEjWgP6LHhwBZeNK1VTsfTFUHCdrfp1bgwQ9xv5ski8PX9rL2dZXvgGDnw",
                         @"[ZNBIP32Sequence serializedMasterPublicKey:]");
}

#pragma mark - testElectrumSequence

- (void)testElectrumSequenceStretchKey
{
    ZNElectrumSequence *seq = [ZNElectrumSequence new];
    NSData *sk = [(id)seq performSelector:@selector(stretchKey:)
                  withObject:@"00000000000000000000000000000000".hexToData];

    NSLog(@"0x00000000000000000000000000000000 stretched = 0x%@", [NSString hexWithData:sk]);
    
    STAssertEqualObjects(sk, @"7c2548ab89ffea8a6579931611969ffc0ed580ccf6048d4230762b981195abe5".hexToData,
                         @"[ZNElectrumSequence stretchKey:]");
}

- (void)testElectrumSequenceMasterPublicKeyFromSeed
{
    ZNElectrumSequence *seq = [ZNElectrumSequence new];
    NSData *mpk = [seq masterPublicKeyFromSeed:@"00000000000000000000000000000000".hexToData];
    
    NSLog(@"mpk from 0x00000000000000000000000000000000 = 0x%@", [NSString hexWithData:mpk]);
    
    STAssertEqualObjects(mpk, @"4e13b0f311a55b8a5db9a32e959da9f011b131019d4cebe6141b9e2c93edcbfc"
                               "0954c358b062a9f94111548e50bde5847a3096b8b7872dcffadb0e9579b9017b".hexToData,
                         @"[ZNElectrumSequence masterPublicKeyFromSeed:]");
}

- (void)testElectrumSequencePublicKey
{
    ZNElectrumSequence *seq = [ZNElectrumSequence new];
    NSData *mpk = [seq masterPublicKeyFromSeed:@"00000000000000000000000000000000".hexToData];
    NSData *pk = [seq publicKey:0 internal:NO masterPublicKey:mpk];
    NSString *addr = [(ZNKey *)[ZNKey keyWithPublicKey:pk] address];
    
    NSLog(@"publicKey:0 = %@", [NSString hexWithData:pk]);
    NSLog(@"addr:0 = %@", addr);
    
    STAssertEqualObjects(pk, @"040900f07c15d3fa441979e71d7ccdcca1afc30a28de07a0525a3d7655dc49cca"
                              "0f844fb0903b3cccc4604107a9de6a0571c4a39996a9e4bd6ab596138ecae54f5".hexToData,
                         @"[ZNElecturmSequence publicKey:forChange:masterPublicKey:]");
    STAssertEqualObjects(addr, @"1FHsTashEBUNPQwC1CwVjnKUxzwgw73pU4", @"[[ZNKey keyWithPublicKey:] address]");
}

- (void)testElectrumSequencePrivateKey
{
    ZNElectrumSequence *seq = [ZNElectrumSequence new];
    NSString *pk = [seq privateKey:0 internal:NO fromSeed:@"00000000000000000000000000000000".hexToData];
    
    NSLog(@"privateKey:0 = %@", pk);
    
    STAssertEqualObjects(pk, @"5Khs7w6fBkogoj1v71Mdt4g8m5kaEyRaortmK56YckgTubgnrhz",
                         @"[ZNElecturmSequence privateKey:forChange:fromSeed:]");

    // Test for correct zero padding of private keys
    pk = [seq privateKey:64 internal:NO fromSeed:@"00000000000000000000000000000000".hexToData];

    NSLog(@"privateKey:64 = %@ = 0x%@", pk, pk.base58checkToHex);

    STAssertEqualObjects(pk.base58checkToHex, @"8000f7f216a82f6beb105728dbbc29e2c13446bfa1078b7bef6e0ceff2c8a1e774",
                         @"[ZNElecturmSequence privateKey:forChange:fromSeed:]");    
}

@end
