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
#import "ZNElectrumMnemonic.h"
#import "ZNZincMnemonic.h"
#import "ZNTransaction.h"
#import "ZNKey.h"
#import "ZNBloomFilter.h"
#import "ZNMerkleBlock.h"
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

//TODO: test standard free transaction no change
//TODO: test standard free transaction with change
//TODO: test transaction over 1k bytes
//TODO: test free transaction who's inputs are too new to hit min free priority
//TODO: test transaction with change below min allowable output
//TODO: test gap limit with gaps in address chain less than the limit

#pragma mark - testKey

- (void)testKeyWithPrivateKey
{
    XCTAssertFalse([@"S6c56bnXQiBjk9mqSYE7ykVQ7NzrRz" isValidBitcoinPrivateKey],
                  @"[NSString+Base58 isValidBitcoinPrivateKey]");

    XCTAssertTrue([@"S6c56bnXQiBjk9mqSYE7ykVQ7NzrRy" isValidBitcoinPrivateKey],
                 @"[NSString+Base58 isValidBitcoinPrivateKey]");

    // mini private key format
    ZNKey *key = [ZNKey keyWithPrivateKey:@"S6c56bnXQiBjk9mqSYE7ykVQ7NzrRy"];
    
    NSLog(@"privKey:S6c56bnXQiBjk9mqSYE7ykVQ7NzrRy = %@", key.address);
#if ! BITCOIN_TESTNET
    STAssertEqualObjects(@"1CciesT23BNionJeXrbxmjc7ywfiyM4oLW", key.address, @"[ZNKey keyWithPrivateKey:]");
#endif

    XCTAssertTrue([@"SzavMBLoXU6kDrqtUVmffv" isValidBitcoinPrivateKey],
                 @"[NSString+Base58 isValidBitcoinPrivateKey]");

    // old mini private key format
    key = [ZNKey keyWithPrivateKey:@"SzavMBLoXU6kDrqtUVmffv"];
    
    NSLog(@"privKey:SzavMBLoXU6kDrqtUVmffv = %@", key.address);
#if ! BITCOIN_TESTNET
    STAssertEqualObjects(@"1CC3X2gu58d6wXUWMffpuzN9JAfTUWu4Kj", key.address, @"[ZNKey keyWithPrivateKey:]");
#endif

    // uncompressed private key
    key = [ZNKey keyWithPrivateKey:@"5Kb8kLf9zgWQnogidDA76MzPL6TsZZY36hWXMssSzNydYXYB9KF"];
    
    NSLog(@"privKey:5Kb8kLf9zgWQnogidDA76MzPL6TsZZY36hWXMssSzNydYXYB9KF = %@", key.address);
#if ! BITCOIN_TESTNET
    STAssertEqualObjects(@"1CC3X2gu58d6wXUWMffpuzN9JAfTUWu4Kj", key.address, @"[ZNKey keyWithPrivateKey:]");
#endif
    
    // uncompressed private key export
    NSLog(@"privKey = %@", key.privateKey);
    XCTAssertEqualObjects(@"5Kb8kLf9zgWQnogidDA76MzPL6TsZZY36hWXMssSzNydYXYB9KF", key.privateKey, @"[ZNKey privateKey]");

    // compressed private key
    key = [ZNKey keyWithPrivateKey:@"KyvGbxRUoofdw3TNydWn2Z78dBHSy2odn1d3wXWN2o3SAtccFNJL"];
    
    NSLog(@"privKey:KyvGbxRUoofdw3TNydWn2Z78dBHSy2odn1d3wXWN2o3SAtccFNJL = %@", key.address);
#if ! BITCOIN_TESTNET
    STAssertEqualObjects(@"1JMsC6fCtYWkTjPPdDrYX3we2aBrewuEM3", key.address, @"[ZNKey keyWithPrivateKey:]");
#endif
    
    // compressed private key export
    NSLog(@"privKey = %@", key.privateKey);
    XCTAssertEqualObjects(@"KyvGbxRUoofdw3TNydWn2Z78dBHSy2odn1d3wXWN2o3SAtccFNJL", key.privateKey,@"[ZNKey privateKey]");
}

#pragma mark - testSign

- (void)testSign
{
    NSData *d, *sig;
    ZNKey *key = [ZNKey keyWithSecret:@"0000000000000000000000000000000000000000000000000000000000000001".hexToData
                  compressed:YES];

    d = [@"Everything should be made as simple as possible, but not simpler."
         dataUsingEncoding:NSUTF8StringEncoding].SHA256;
    sig = [key sign:d];

    XCTAssertEqualObjects(sig, @"3044022033a69cd2065432a30f3d1ce4eb0d59b8ab58c74f27c41a7fdb5696ad4e6108c902206f807982866"
                         "f785d3f6418d24163ddae117b7db4d5fdf0071de069fa54342262".hexToData, @"[ZNKey sign:]");

    key = [ZNKey keyWithSecret:@"fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140".hexToData
           compressed:YES];
    d = [@"Equations are more important to me, because politics is for the present, but an equation is something for "
         "eternity." dataUsingEncoding:NSUTF8StringEncoding].SHA256;
    sig = [key sign:d];

    XCTAssertEqualObjects(sig, @"3044022054c4a33c6423d689378f160a7ff8b61330444abb58fb470f96ea16d99d4a2fed022007082304410"
                         "efa6b2943111b6a4e0aaa7b7db55a07e9861d1fb3cb1f421044a5".hexToData, @"[ZNKey sign:]");

    key = [ZNKey keyWithSecret:@"fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140".hexToData
           compressed:YES];
    d = [@"Not only is the Universe stranger than we think, it is stranger than we can think."
         dataUsingEncoding:NSUTF8StringEncoding].SHA256;
    sig = [key sign:d];

    XCTAssertEqualObjects(sig, @"3045022100ff466a9f1b7b273e2f4c3ffe032eb2e814121ed18ef84665d0f515360dab3dd002206fc95f513"
                         "2e5ecfdc8e5e6e616cc77151455d46ed48f5589b7db7771a332b283".hexToData, @"[ZNKey sign:]");

    key = [ZNKey keyWithSecret:@"0000000000000000000000000000000000000000000000000000000000000001".hexToData
           compressed:YES];
    d = [@"How wonderful that we have met with a paradox. Now we have some hope of making progress."
         dataUsingEncoding:NSUTF8StringEncoding].SHA256;
    sig = [key sign:d];

    XCTAssertEqualObjects(sig, @"3045022100c0dafec8251f1d5010289d210232220b03202cba34ec11fec58b3e93a85b91d3022075afdc06b"
                         "7d6322a590955bf264e7aaa155847f614d80078a90292fe205064d3".hexToData, @"[ZNKey sign:]");

    key = [ZNKey keyWithSecret:@"69ec59eaa1f4f2e36b639716b7c30ca86d9a5375c7b38d8918bd9c0ebc80ba64".hexToData
           compressed:YES];
    d = [@"Computer science is no more about computers than astronomy is about telescopes."
         dataUsingEncoding:NSUTF8StringEncoding].SHA256;
    sig = [key sign:d];

    XCTAssertEqualObjects(sig, @"304402207186363571d65e084e7f02b0b77c3ec44fb1b257dee26274c38c928986fea45d02200de0b38e068"
                         "07e46bda1f1e293f4f6323e854c86d58abdd00c46c16441085df6".hexToData, @"[ZNKey sign:]");

    key = [ZNKey keyWithSecret:@"00000000000000000000000000007246174ab1e92e9149c6e446fe194d072637".hexToData
           compressed:YES];
    d = [@"...if you aren't, at any given time, scandalized by code you wrote five or even three years ago, you're not "
         "learning anywhere near enough" dataUsingEncoding:NSUTF8StringEncoding].SHA256;
    sig = [key sign:d];

    XCTAssertEqualObjects(sig, @"3045022100fbfe5076a15860ba8ed00e75e9bd22e05d230f02a936b653eb55b61c99dda48702200e68880eb"
                         "b0050fe4312b1b1eb0899e1b82da89baa5b895f612619edf34cbd37".hexToData, @"[ZNKey sign:]");

    key = [ZNKey keyWithSecret:@"000000000000000000000000000000000000000000056916d0f9b31dc9b637f3".hexToData
           compressed:YES];
    d = [@"The question of whether computers can think is like the question of whether submarines can swim."
         dataUsingEncoding:NSUTF8StringEncoding].SHA256;
    sig = [key sign:d];

    XCTAssertEqualObjects(sig, @"3045022100cde1302d83f8dd835d89aef803c74a119f561fbaef3eb9129e45f30de86abbf9022006ce643f5"
                         "049ee1f27890467b77a6a8e11ec4661cc38cd8badf90115fbd03cef".hexToData, @"[ZNKey sign:]");
}

#pragma mark - testPaymentRequest

//TODO: test valid request with no arguments
//TODO: test valid request with known arguments
//TODO: test valid request with unkown arguments
//TODO: test invalid bitcoin address
//TODO: test invalid request with unkown required arguments

#pragma mark - testTransaction

- (void)testTransaction
{
    NSData *hash = [NSMutableData dataWithLength:32], *script = [NSMutableData dataWithLength:136];
    NSString *addr = @"1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa";
    ZNTransaction *tx = [[ZNTransaction alloc] initWithInputHashes:@[hash] inputIndexes:@[@0] inputScripts:@[script]
                         outputAddresses:@[addr, addr] outputAmounts:@[@100000000, @4900000000]];
    
    NSUInteger height = [tx blockHeightUntilFreeForAmounts:@[@5000000000] withBlockHeights:@[@1]];
    uint64_t priority = [tx priorityForAmounts:@[@5000000000] withAges:@[@(height - 1)]];
    
    NSLog(@"height = %lu", (unsigned long)height);
    NSLog(@"priority = %llu", priority);
    
    XCTAssertTrue(priority >= TX_FREE_MIN_PRIORITY, @"[ZNTransaction heightUntilFreeFor:atHeights:]");

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
    
    NSLog(@"height = %lu", (unsigned long)height);
    NSLog(@"priority = %llu", priority);
    
    XCTAssertTrue(priority >= TX_FREE_MIN_PRIORITY, @"[ZNTransaction heightUntilFreeFor:atHeights:]");
    
    NSData *d = tx.data, *d2 = nil;
    
    tx = [[ZNTransaction alloc] initWithData:d];
    d2 = tx.data;
    
    XCTAssertEqualObjects(d, d2, @"[ZNTransaction initWithData:]");
}

#pragma mark - testZincMnemonic

//TODO: test zinc mnemonic
//- (void)testZincMnemonicDecodePhrase
//{
//    id<ZNMnemonic> mnemonic = [ZNZincMnemonic sharedInstance];
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

- (void)testZincMnemonicEncodePhrase
{
    id<ZNMnemonic> mnemonic = [ZNZincMnemonic sharedInstance];
    
    NSString *s = [mnemonic encodePhrase:@"00285dfe00285e0100285e0400285e07".hexToData];
    
    NSLog(@"0x00285dfe00285e0100285e0400285e07 = %@", s);
    
    XCTAssertEqualObjects([mnemonic decodePhrase:s], @"00285dfe00285e0100285e0400285e07".hexToData,
                         @"[ZNWallet encodePhrase:]");
    
    s = [mnemonic encodePhrase:@"00000000000000000000000000000000".hexToData];
    
    NSLog(@"0x00000000000000000000000000000000 = %@", s);

    XCTAssertEqualObjects([mnemonic decodePhrase:s], @"00000000000000000000000000000000".hexToData,
                         @"[ZNWallet encodePhrase:]");
    
    s = [mnemonic encodePhrase:@"fea983ac0028608e0028609100286094".hexToData];
    
    NSLog(@"0xfea983ac0028608e0028609100286094 = %@", s);
    
    XCTAssertEqualObjects([mnemonic decodePhrase:s], @"fea983ac0028608e0028609100286094".hexToData,
                         @"[ZNWallet encodePhrase:]");
    
    s = [mnemonic encodePhrase:@"8d02be487e1953ce2dd6c186fcc97e65".hexToData];
    
    NSLog(@"0x8d02be487e1953ce2dd6c186fcc97e65 = %@", s);
    
    XCTAssertEqualObjects([mnemonic decodePhrase:s], @"8d02be487e1953ce2dd6c186fcc97e65".hexToData,
                         @"[ZNWallet encodePhrase:]");
}

#pragma mark - testElectrumMnemonic

- (void)testElectrumMnemonicDecodePhrase
{
    id<ZNMnemonic> mnemonic = [ZNElectrumMnemonic sharedInstance];

    NSData *d = [mnemonic decodePhrase:@"like just love know never want time out there make look eye"];

    NSLog(@"like just love know never want time out there make look eye = 0x%@", [NSString hexWithData:d]);
    
    XCTAssertEqualObjects(d, @"00285dfe00285e0100285e0400285e07".hexToData, @"[ZNWallet decodePhrase:]");
    
    d = [mnemonic decodePhrase:@"kick chair mask master passion quick raise smooth unless wander actually broke"];
    
    NSLog(@"kick chair mask master passion quick raise smooth unless wander actually broke = 0x%@",
          [NSString hexWithData:d]);
    
    XCTAssertEqualObjects(d, @"fea983ac0028608e0028609100286094".hexToData, @"[ZNWallet decodePhrase:]");
    
    // test of phrase with trailing space
    d = [mnemonic
         decodePhrase:@"kick quiet student ignore cruel danger describe accident eager darkness embrace suppose "];
    
    NSLog(@"kick quiet student ignore cruel danger describe accident eager darkness embrace suppose = 0x%@",
          [NSString hexWithData:d]);
    
    XCTAssertEqualObjects(d, @"8d02be487e1953ce2dd6c186fcc97e65".hexToData, @"[ZNWallet decodePhrase:]");
}

- (void)testElectrumMnemonicEncodePhrase
{
    id<ZNMnemonic> mnemonic = [ZNElectrumMnemonic sharedInstance];
    
    NSString *s = [mnemonic encodePhrase:@"00285dfe00285e0100285e0400285e07".hexToData];
    
    NSLog(@"0x00285dfe00285e0100285e0400285e07 = %@", s);
    
    XCTAssertEqualObjects(s, @"like just love know never want time out there make look eye",
                         @"[ZNWallet encodePhrase:]");
    
    s = [mnemonic encodePhrase:@"00000000000000000000000000000000".hexToData];

    NSLog(@"0x00285dfe00285e0100285e0400285e07 = %@", s);
    
    s = [mnemonic encodePhrase:@"fea983ac0028608e0028609100286094".hexToData];
    
    NSLog(@"0x00285dfe00285e0100285e0400285e07 = %@", s);
    
    XCTAssertEqualObjects(s, @"kick chair mask master passion quick raise smooth unless wander actually broke",
                         @"[ZNWallet encodePhrase:]");
    
    s = [mnemonic encodePhrase:@"8d02be487e1953ce2dd6c186fcc97e65".hexToData];
    
    NSLog(@"0x8d02be487e1953ce2dd6c186fcc97e65 = %@", s);
    
    XCTAssertEqualObjects(s, @"kick quiet student ignore cruel danger describe accident eager darkness embrace suppose",
                         @"[ZNWallet encodePhrase:]");    
}

#pragma mark - testBIP32Sequence

- (void)testBIP32SequencePrivateKey
{
    ZNBIP32Sequence *seq = [ZNBIP32Sequence new];
    NSData *seed = @"000102030405060708090a0b0c0d0e0f".hexToData;
    NSString *pk = [seq privateKey:2 | 0x80000000 internal:YES fromSeed:seed];
    NSData *d = pk.base58checkToData;

    NSLog(@"000102030405060708090a0b0c0d0e0f/0'/1/2' prv = %@", [NSString hexWithData:d]);

    XCTAssertEqualObjects(d, @"80cbce0d719ecf7431d88e6a89fa1483e02e35092af60c042b1df2ff59fa424dca01".hexToData,
                         @"[ZNBIP32Sequence privateKey:internal:fromSeed:]");

    // Test for correct zero padding of private keys, a nasty potential bug
    pk = [seq privateKey:97 internal:NO fromSeed:seed];
    d = pk.base58checkToData;

    NSLog(@"000102030405060708090a0b0c0d0e0f/0'/0/97 prv = %@", [NSString hexWithData:d]);

    XCTAssertEqualObjects(d, @"8000136c1ad038f9a00871895322a487ed14f1cdc4d22ad351cfa1a0d235975dd701".hexToData,
                         @"[ZNBIP32Sequence privateKey:internal:fromSeed:]");
}

- (void)testBIP32SequenceMasterPublicKeyFromSeed
{
    ZNBIP32Sequence *seq = [ZNBIP32Sequence new];
    NSData *seed = @"000102030405060708090a0b0c0d0e0f".hexToData;
    NSData *mpk = [seq masterPublicKeyFromSeed:seed];
    
    NSLog(@"000102030405060708090a0b0c0d0e0f/0' pub+chain = %@", [NSString hexWithData:mpk]);
    
    XCTAssertEqualObjects(mpk, @"3442193e"
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
    
    //TODO: verify the value of pub using the output of some other implementation
}

- (void)testBIP32SequenceSerializedPrivateMasterFromSeed
{
    ZNBIP32Sequence *seq = [ZNBIP32Sequence new];
    NSData *seed = @"000102030405060708090a0b0c0d0e0f".hexToData;
    NSString *xprv = [seq serializedPrivateMasterFromSeed:seed];
    
    NSLog(@"000102030405060708090a0b0c0d0e0f xpriv = %@", xprv);
    
    XCTAssertEqualObjects(xprv,
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
    
    XCTAssertEqualObjects(xpub,
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
    
    XCTAssertEqualObjects(sk, @"7c2548ab89ffea8a6579931611969ffc0ed580ccf6048d4230762b981195abe5".hexToData,
                         @"[ZNElectrumSequence stretchKey:]");
}

- (void)testElectrumSequenceMasterPublicKeyFromSeed
{
    ZNElectrumSequence *seq = [ZNElectrumSequence new];
    NSData *mpk = [seq masterPublicKeyFromSeed:@"00000000000000000000000000000000".hexToData];
    
    NSLog(@"mpk from 0x00000000000000000000000000000000 = 0x%@", [NSString hexWithData:mpk]);
    
    XCTAssertEqualObjects(mpk, @"4e13b0f311a55b8a5db9a32e959da9f011b131019d4cebe6141b9e2c93edcbfc"
                               "0954c358b062a9f94111548e50bde5847a3096b8b7872dcffadb0e9579b9017b".hexToData,
                         @"[ZNElectrumSequence masterPublicKeyFromSeed:]");
}

- (void)testElectrumSequencePublicKey
{
    ZNElectrumSequence *seq = [ZNElectrumSequence new];
    NSData *mpk = [seq masterPublicKeyFromSeed:@"00000000000000000000000000000000".hexToData];
    NSData *pubkey = [seq publicKey:0 internal:NO masterPublicKey:mpk];
    NSString *addr = [(ZNKey *)[ZNKey keyWithPublicKey:pubkey] address];
    
    NSLog(@"publicKey:0 = %@", [NSString hexWithData:pubkey]);
    NSLog(@"addr:0 = %@", addr);
    
    XCTAssertEqualObjects(pubkey, @"040900f07c15d3fa441979e71d7ccdcca1afc30a28de07a0525a3d7655dc49cca"
                                  "0f844fb0903b3cccc4604107a9de6a0571c4a39996a9e4bd6ab596138ecae54f5".hexToData,
                         @"[ZNElectrumSequence publicKey:forChange:masterPublicKey:]");
#if ! BITCOIN_TESTNET
    STAssertEqualObjects(addr, @"1FHsTashEBUNPQwC1CwVjnKUxzwgw73pU4", @"[[ZNKey keyWithPublicKey:] address]");
#endif
}

- (void)testElectrumSequencePrivateKey
{
    ZNElectrumSequence *seq = [ZNElectrumSequence new];
    NSString *pk = [seq privateKey:0 internal:NO fromSeed:@"00000000000000000000000000000000".hexToData];
    
    NSLog(@"privateKey:0 = %@", pk);
    
    XCTAssertEqualObjects(pk, @"5Khs7w6fBkogoj1v71Mdt4g8m5kaEyRaortmK56YckgTubgnrhz",
                         @"[ZNElectrumSequence privateKey:forChange:fromSeed:]");

    // Test for correct zero padding of private keys
    pk = [seq privateKey:64 internal:NO fromSeed:@"00000000000000000000000000000000".hexToData];

    NSLog(@"privateKey:64 = %@ = 0x%@", pk, pk.base58checkToHex);

    XCTAssertEqualObjects(pk.base58checkToHex, @"8000f7f216a82f6beb105728dbbc29e2c13446bfa1078b7bef6e0ceff2c8a1e774",
                         @"[ZNElectrumSequence privateKey:forChange:fromSeed:]");    
}

#pragma mark - testBloomFilter

- (void)testBloomFilter
{
    ZNBloomFilter *f = [ZNBloomFilter filterWithFalsePositiveRate:.01 forElementCount:3 tweak:0 flags:BLOOM_UPDATE_ALL];

    [f insertData:@"99108ad8ed9bb6274d3980bab5a85c048f0950c8".hexToData];

    XCTAssertTrue([f containsData:@"99108ad8ed9bb6274d3980bab5a85c048f0950c8".hexToData],
                 @"[ZNBloomFilter containsData:]");

    // one bit difference
    XCTAssertFalse([f containsData:@"19108ad8ed9bb6274d3980bab5a85c048f0950c8".hexToData],
                  @"[ZNBloomFilter containsData:]");

    [f insertData:@"b5a2c786d9ef4658287ced5914b37a1b4aa32eee".hexToData];

    XCTAssertTrue([f containsData:@"b5a2c786d9ef4658287ced5914b37a1b4aa32eee".hexToData],
                 @"[ZNBloomFilter containsData:]");

    [f insertData:@"b9300670b4c5366e95b2699e8b18bc75e5f729c5".hexToData];

    XCTAssertTrue([f containsData:@"b9300670b4c5366e95b2699e8b18bc75e5f729c5".hexToData],
                 @"[ZNBloomFilter containsData:]");

    // check against satoshi client output
    XCTAssertEqualObjects(@"03614e9b050000000000000001".hexToData, f.data, @"[ZNBloomFilter data:]");
}

- (void)testBloomFilterWithTweak
{
    ZNBloomFilter *f = [ZNBloomFilter filterWithFalsePositiveRate:.01 forElementCount:3 tweak:2147483649
                        flags:BLOOM_UPDATE_P2PUBKEY_ONLY];

    [f insertData:@"99108ad8ed9bb6274d3980bab5a85c048f0950c8".hexToData];
    
    XCTAssertTrue([f containsData:@"99108ad8ed9bb6274d3980bab5a85c048f0950c8".hexToData],
                 @"[ZNBloomFilter containsData:]");
    
    // one bit difference
    XCTAssertFalse([f containsData:@"19108ad8ed9bb6274d3980bab5a85c048f0950c8".hexToData],
                  @"[ZNBloomFilter containsData:]");
    
    [f insertData:@"b5a2c786d9ef4658287ced5914b37a1b4aa32eee".hexToData];
    
    XCTAssertTrue([f containsData:@"b5a2c786d9ef4658287ced5914b37a1b4aa32eee".hexToData],
                 @"[ZNBloomFilter containsData:]");
    
    [f insertData:@"b9300670b4c5366e95b2699e8b18bc75e5f729c5".hexToData];
    
    XCTAssertTrue([f containsData:@"b9300670b4c5366e95b2699e8b18bc75e5f729c5".hexToData],
                 @"[ZNBloomFilter containsData:]");

    // check against satoshi client output
    XCTAssertEqualObjects(@"03ce4299050000000100008002".hexToData, f.data, @"[ZNBloomFilter data:]");
}

#pragma mark - testMerkleBlock

- (void)testMerkleBlock
{
    // block 10001 filtered to include only transactions 0, 1, 2, and 6
    NSData *block = @"0100000006e533fd1ada86391f3f6c343204b0d278d4aaec1c0b20aa27ba0300000000006abbb3eb3d733a9fe18967fd7"
                     "d4c117e4ccbbac5bec4d910d900b3ae0793e77f54241b4d4c86041b4089cc9b0c000000084c30b63cfcdc2d35e3329421"
                     "b9805ef0c6565d35381ca857762ea0b3a5a128bbca5065ff9617cbcba45eb23726df6498a9b9cafed4f54cbab9d227b00"
                     "35ddefbbb15ac1d57d0182aaee61c74743a9c4f785895e563909bafec45c9a2b0ff3181d77706be8b1dcc91112eada86d"
                     "424e2d0a8907c3488b6e44fda5a74a25cbc7d6bb4fa04245f4ac8a1a571d5537eac24adca1454d65eda446055479af6c6"
                     "d4dd3c9ab658448c10b6921b7a4ce3021eb22ed6bb6a7fde1e5bcc4b1db6615c6abc5ca042127bfaf9f44ebce29cb29c6"
                     "df9d05b47f35b2edff4f0064b578ab741fa78276222651209fe1a2c4c0fa1c58510aec8b090dd1eb1f82f9d261b8273b5"
                     "25b02ff1a".hexToData;
    
    ZNMerkleBlock *b = [ZNMerkleBlock blockWithMessage:block];
    
    XCTAssertEqualObjects(b.blockHash,
                         @"00000000000080b66c911bd5ba14a74260057311eaeb1982802f7010f1a9f090".hexToData.reverse,
                         @"[ZNMerkleBlock blockHash]");

    XCTAssertTrue(b.valid, @"[ZNMerkleBlock isValid]");

    XCTAssertTrue([b containsTxHash:@"4c30b63cfcdc2d35e3329421b9805ef0c6565d35381ca857762ea0b3a5a128bb".hexToData],
                 @"[ZNMerkleBlock containsTxHash:]");

    XCTAssertTrue(b.txHashes.count == 4, @"[ZNMerkleBlock txHashes]");
    XCTAssertEqualObjects(b.txHashes[0], @"4c30b63cfcdc2d35e3329421b9805ef0c6565d35381ca857762ea0b3a5a128bb".hexToData,
                         @"[ZNMerkleBlock txHashes]");
    XCTAssertEqualObjects(b.txHashes[1], @"ca5065ff9617cbcba45eb23726df6498a9b9cafed4f54cbab9d227b0035ddefb".hexToData,
                         @"[ZNMerkleBlock txHashes]");
    XCTAssertEqualObjects(b.txHashes[2], @"bb15ac1d57d0182aaee61c74743a9c4f785895e563909bafec45c9a2b0ff3181".hexToData,
                         @"[ZNMerkleBlock txHashes]");
    XCTAssertEqualObjects(b.txHashes[3], @"c9ab658448c10b6921b7a4ce3021eb22ed6bb6a7fde1e5bcc4b1db6615c6abc5".hexToData,
                         @"[ZNMerkleBlock txHashes]");
    
    //TODO: test a block with an odd number of tree rows both at the tx level and merkle node level
}

@end
