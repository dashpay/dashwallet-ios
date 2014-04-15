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
#import "ZNBIP39Mnemonic.h"
#import "ZNTransaction.h"
#import "ZNKey.h"
#import "ZNKey+BIP38.h"
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

#if ! BITCOIN_TESTNET
- (void)testKeyWithPrivateKey
{
    XCTAssertFalse([@"S6c56bnXQiBjk9mqSYE7ykVQ7NzrRz" isValidBitcoinPrivateKey],
                  @"[NSString+Base58 isValidBitcoinPrivateKey]");

    XCTAssertTrue([@"S6c56bnXQiBjk9mqSYE7ykVQ7NzrRy" isValidBitcoinPrivateKey],
                 @"[NSString+Base58 isValidBitcoinPrivateKey]");

    // mini private key format
    ZNKey *key = [ZNKey keyWithPrivateKey:@"S6c56bnXQiBjk9mqSYE7ykVQ7NzrRy"];
    
    NSLog(@"privKey:S6c56bnXQiBjk9mqSYE7ykVQ7NzrRy = %@", key.address);
    XCTAssertEqualObjects(@"1CciesT23BNionJeXrbxmjc7ywfiyM4oLW", key.address, @"[ZNKey keyWithPrivateKey:]");
    XCTAssertTrue([@"SzavMBLoXU6kDrqtUVmffv" isValidBitcoinPrivateKey],
                 @"[NSString+Base58 isValidBitcoinPrivateKey]");

    // old mini private key format
    key = [ZNKey keyWithPrivateKey:@"SzavMBLoXU6kDrqtUVmffv"];
    
    NSLog(@"privKey:SzavMBLoXU6kDrqtUVmffv = %@", key.address);
    XCTAssertEqualObjects(@"1CC3X2gu58d6wXUWMffpuzN9JAfTUWu4Kj", key.address, @"[ZNKey keyWithPrivateKey:]");

    // uncompressed private key
    key = [ZNKey keyWithPrivateKey:@"5Kb8kLf9zgWQnogidDA76MzPL6TsZZY36hWXMssSzNydYXYB9KF"];
    
    NSLog(@"privKey:5Kb8kLf9zgWQnogidDA76MzPL6TsZZY36hWXMssSzNydYXYB9KF = %@", key.address);
    XCTAssertEqualObjects(@"1CC3X2gu58d6wXUWMffpuzN9JAfTUWu4Kj", key.address, @"[ZNKey keyWithPrivateKey:]");

    // uncompressed private key export
    NSLog(@"privKey = %@", key.privateKey);
    XCTAssertEqualObjects(@"5Kb8kLf9zgWQnogidDA76MzPL6TsZZY36hWXMssSzNydYXYB9KF", key.privateKey,
                          @"[ZNKey privateKey]");

    // compressed private key
    key = [ZNKey keyWithPrivateKey:@"KyvGbxRUoofdw3TNydWn2Z78dBHSy2odn1d3wXWN2o3SAtccFNJL"];
    
    NSLog(@"privKey:KyvGbxRUoofdw3TNydWn2Z78dBHSy2odn1d3wXWN2o3SAtccFNJL = %@", key.address);
    XCTAssertEqualObjects(@"1JMsC6fCtYWkTjPPdDrYX3we2aBrewuEM3", key.address, @"[ZNKey keyWithPrivateKey:]");

    // compressed private key export
    NSLog(@"privKey = %@", key.privateKey);
    XCTAssertEqualObjects(@"KyvGbxRUoofdw3TNydWn2Z78dBHSy2odn1d3wXWN2o3SAtccFNJL", key.privateKey,
                          @"[ZNKey privateKey]");
}
#endif

#pragma mark - testKeyWithBIP38Key

#if ! BITCOIN_TESTNET
- (void)testKeyWithBIP38Key
{
    NSString *intercode, *confcode, *privkey;
    ZNKey *key;

    //TODO: XXXX generate a bip38 key from a secret that's outside the order of secp256k1

    // non EC multiplied, uncompressed
    key = [ZNKey keyWithBIP38Key:@"6PRVWUbkzzsbcVac2qwfssoUJAN1Xhrg6bNk8J7Nzm5H7kxEbn2Nh2ZoGg"
           andPassphrase:@"TestingOneTwoThree"];
    NSLog(@"privKey = %@", key.privateKey);
    XCTAssertEqualObjects(@"5KN7MzqK5wt2TP1fQCYyHBtDrXdJuXbUzm4A9rKAteGu3Qi5CVR", key.privateKey,
                          @"[ZNKey keyWithBIP38Key:andPassphrase:]");
    XCTAssertEqualObjects([key BIP38KeyWithPassphrase:@"TestingOneTwoThree"],
                          @"6PRVWUbkzzsbcVac2qwfssoUJAN1Xhrg6bNk8J7Nzm5H7kxEbn2Nh2ZoGg",
                          @"[ZNKey BIP38KeyWithPassphrase:]");

    key = [ZNKey keyWithBIP38Key:@"6PRNFFkZc2NZ6dJqFfhRoFNMR9Lnyj7dYGrzdgXXVMXcxoKTePPX1dWByq"
           andPassphrase:@"Satoshi"];
    NSLog(@"privKey = %@", key.privateKey);
    XCTAssertEqualObjects(@"5HtasZ6ofTHP6HCwTqTkLDuLQisYPah7aUnSKfC7h4hMUVw2gi5", key.privateKey,
                          @"[ZNKey keyWithBIP38Key:andPassphrase:]");
    XCTAssertEqualObjects([key BIP38KeyWithPassphrase:@"Satoshi"],
                          @"6PRNFFkZc2NZ6dJqFfhRoFNMR9Lnyj7dYGrzdgXXVMXcxoKTePPX1dWByq",
                          @"[ZNKey BIP38KeyWithPassphrase:]");

    // non EC multiplied, compressed
    key = [ZNKey keyWithBIP38Key:@"6PYNKZ1EAgYgmQfmNVamxyXVWHzK5s6DGhwP4J5o44cvXdoY7sRzhtpUeo"
           andPassphrase:@"TestingOneTwoThree"];
    NSLog(@"privKey = %@", key.privateKey);
    XCTAssertEqualObjects(@"L44B5gGEpqEDRS9vVPz7QT35jcBG2r3CZwSwQ4fCewXAhAhqGVpP", key.privateKey,
                          @"[ZNKey keyWithBIP38Key:andPassphrase:]");
    XCTAssertEqualObjects([key BIP38KeyWithPassphrase:@"TestingOneTwoThree"],
                          @"6PYNKZ1EAgYgmQfmNVamxyXVWHzK5s6DGhwP4J5o44cvXdoY7sRzhtpUeo",
                          @"[ZNKey BIP38KeyWithPassphrase:]");

    key = [ZNKey keyWithBIP38Key:@"6PYLtMnXvfG3oJde97zRyLYFZCYizPU5T3LwgdYJz1fRhh16bU7u6PPmY7"
           andPassphrase:@"Satoshi"];
    NSLog(@"privKey = %@", key.privateKey);
    XCTAssertEqualObjects(@"KwYgW8gcxj1JWJXhPSu4Fqwzfhp5Yfi42mdYmMa4XqK7NJxXUSK7", key.privateKey,
                          @"[ZNKey keyWithBIP38Key:andPassphrase:]");
    XCTAssertEqualObjects([key BIP38KeyWithPassphrase:@"Satoshi"],
                          @"6PYLtMnXvfG3oJde97zRyLYFZCYizPU5T3LwgdYJz1fRhh16bU7u6PPmY7",
                          @"[ZNKey BIP38KeyWithPassphrase:]");

    // EC multiplied, uncompressed, no lot/sequence number
    key = [ZNKey keyWithBIP38Key:@"6PfQu77ygVyJLZjfvMLyhLMQbYnu5uguoJJ4kMCLqWwPEdfpwANVS76gTX"
           andPassphrase:@"TestingOneTwoThree"];
    NSLog(@"privKey = %@", key.privateKey);
    XCTAssertEqualObjects(@"5K4caxezwjGCGfnoPTZ8tMcJBLB7Jvyjv4xxeacadhq8nLisLR2", key.privateKey,
                          @"[ZNKey keyWithBIP38Key:andPassphrase:]");
    intercode = [ZNKey BIP38IntermediateCodeWithSalt:0xa50dba6772cb9383llu andPassphrase:@"TestingOneTwoThree"];
    NSLog(@"intercode = %@", intercode);
    privkey = [ZNKey BIP38KeyWithIntermediateCode:intercode
               seedb:@"99241d58245c883896f80843d2846672d7312e6195ca1a6c".hexToData compressed:NO
               confirmationCode:&confcode];
    NSLog(@"confcode = %@", confcode);
    XCTAssertEqualObjects(@"6PfQu77ygVyJLZjfvMLyhLMQbYnu5uguoJJ4kMCLqWwPEdfpwANVS76gTX", privkey,
                          @"[ZNKey BIP38KeyWithIntermediateCode:]");
    XCTAssertTrue([ZNKey confirmWithBIP38ConfirmationCode:confcode address:@"1PE6TQi6HTVNz5DLwB1LcpMBALubfuN2z2"
                   passphrase:@"TestingOneTwoThree"], @"[ZNKey confirmWithBIP38ConfirmationCode:]");

    key = [ZNKey keyWithBIP38Key:@"6PfLGnQs6VZnrNpmVKfjotbnQuaJK4KZoPFrAjx1JMJUa1Ft8gnf5WxfKd"
           andPassphrase:@"Satoshi"];
    NSLog(@"privKey = %@", key.privateKey);
    XCTAssertEqualObjects(@"5KJ51SgxWaAYR13zd9ReMhJpwrcX47xTJh2D3fGPG9CM8vkv5sH", key.privateKey,
                          @"[ZNKey keyWithBIP38Key:andPassphrase:]");
    intercode = [ZNKey BIP38IntermediateCodeWithSalt:0x67010a9573418906llu andPassphrase:@"Satoshi"];
    NSLog(@"intercode = %@", intercode);
    privkey = [ZNKey BIP38KeyWithIntermediateCode:intercode
               seedb:@"49111e301d94eab339ff9f6822ee99d9f49606db3b47a497".hexToData compressed:NO
               confirmationCode:&confcode];
    NSLog(@"confcode = %@", confcode);
    XCTAssertEqualObjects(@"6PfLGnQs6VZnrNpmVKfjotbnQuaJK4KZoPFrAjx1JMJUa1Ft8gnf5WxfKd", privkey,
                          @"[ZNKey BIP38KeyWithIntermediateCode:]");
    XCTAssertTrue([ZNKey confirmWithBIP38ConfirmationCode:confcode address:@"1CqzrtZC6mXSAhoxtFwVjz8LtwLJjDYU3V"
                   passphrase:@"Satoshi"], @"[ZNKey confirmWithBIP38ConfirmationCode:]");

    // EC multiplied, uncompressed, with lot/sequence number
    key = [ZNKey keyWithBIP38Key:@"6PgNBNNzDkKdhkT6uJntUXwwzQV8Rr2tZcbkDcuC9DZRsS6AtHts4Ypo1j"
           andPassphrase:@"MOLON LABE"];
    NSLog(@"privKey = %@", key.privateKey);
    XCTAssertEqualObjects(@"5JLdxTtcTHcfYcmJsNVy1v2PMDx432JPoYcBTVVRHpPaxUrdtf8", key.privateKey,
                          @"[ZNKey keyWithBIP38Key:andPassphrase:]");
    intercode = [ZNKey BIP38IntermediateCodeWithLot:263183 sequence:1 salt:0x4fca5a97u passphrase:@"MOLON LABE"];
    NSLog(@"intercode = %@", intercode);
    privkey = [ZNKey BIP38KeyWithIntermediateCode:intercode
               seedb:@"87a13b07858fa753cd3ab3f1c5eafb5f12579b6c33c9a53f".hexToData compressed:NO
               confirmationCode:&confcode];
    NSLog(@"confcode = %@", confcode);
    XCTAssertEqualObjects(@"6PgNBNNzDkKdhkT6uJntUXwwzQV8Rr2tZcbkDcuC9DZRsS6AtHts4Ypo1j", privkey,
                          @"[ZNKey BIP38KeyWithIntermediateCode:]");
    XCTAssertTrue([ZNKey confirmWithBIP38ConfirmationCode:confcode address:@"1Jscj8ALrYu2y9TD8NrpvDBugPedmbj4Yh"
                   passphrase:@"MOLON LABE"], @"[ZNKey confirmWithBIP38ConfirmationCode:]");

    key = [ZNKey keyWithBIP38Key:@"6PgGWtx25kUg8QWvwuJAgorN6k9FbE25rv5dMRwu5SKMnfpfVe5mar2ngH"
           andPassphrase:@"\u039c\u039f\u039b\u03a9\u039d \u039b\u0391\u0392\u0395"];
    NSLog(@"privKey = %@", key.privateKey);
    XCTAssertEqualObjects(@"5KMKKuUmAkiNbA3DazMQiLfDq47qs8MAEThm4yL8R2PhV1ov33D", key.privateKey,
                          @"[ZNKey keyWithBIP38Key:andPassphrase:]");
    intercode = [ZNKey BIP38IntermediateCodeWithLot:806938 sequence:1 salt:0xc40ea76fu
                 passphrase:@"\u039c\u039f\u039b\u03a9\u039d \u039b\u0391\u0392\u0395"];
    NSLog(@"intercode = %@", intercode);
    privkey = [ZNKey BIP38KeyWithIntermediateCode:intercode
               seedb:@"03b06a1ea7f9219ae364560d7b985ab1fa27025aaa7e427a".hexToData compressed:NO
               confirmationCode:&confcode];
    NSLog(@"confcode = %@", confcode);
    XCTAssertEqualObjects(@"6PgGWtx25kUg8QWvwuJAgorN6k9FbE25rv5dMRwu5SKMnfpfVe5mar2ngH", privkey,
                          @"[ZNKey BIP38KeyWithIntermediateCode:]");
    XCTAssertTrue([ZNKey confirmWithBIP38ConfirmationCode:confcode address:@"1Lurmih3KruL4xDB5FmHof38yawNtP9oGf"
                   passphrase:@"\u039c\u039f\u039b\u03a9\u039d \u039b\u0391\u0392\u0395"],
                  @"[ZNKey confirmWithBIP38ConfirmationCode:]");

    // password NFC unicode normalization test
    key = [ZNKey keyWithBIP38Key:@"6PRW5o9FLp4gJDDVqJQKJFTpMvdsSGJxMYHtHaQBF3ooa8mwD69bapcDQn"
           andPassphrase:@"\u03D2\u0301\x00\U00010400\U0001F4A9"];
    NSLog(@"privKey = %@", key.privateKey);
    XCTAssertEqualObjects(@"5Jajm8eQ22H3pGWLEVCXyvND8dQZhiQhoLJNKjYXk9roUFTMSZ4", key.privateKey,
                          @"[ZNKey keyWithBIP38Key:andPassphrase:]");

    // incorrect password test
    key = [ZNKey keyWithBIP38Key:@"6PRW5o9FLp4gJDDVqJQKJFTpMvdsSGJxMYHtHaQBF3ooa8mwD69bapcDQn" andPassphrase:@"foobar"];
    NSLog(@"privKey = %@", key.privateKey);
    XCTAssertNil(key, @"[ZNKey keyWithBIP38Key:andPassphrase:]");
}
#endif

#pragma mark - testSign

- (void)testSign
{
    NSData *d, *sig;
    ZNKey *key = [ZNKey keyWithSecret:@"0000000000000000000000000000000000000000000000000000000000000001".hexToData
                  compressed:YES];

    d = [@"Everything should be made as simple as possible, but not simpler."
         dataUsingEncoding:NSUTF8StringEncoding].SHA256;
    sig = [key sign:d];

    XCTAssertEqualObjects(sig, @"3044022033a69cd2065432a30f3d1ce4eb0d59b8ab58c74f27c41a7fdb5696ad4e6108c902206f80798286"
                          "6f785d3f6418d24163ddae117b7db4d5fdf0071de069fa54342262".hexToData, @"[ZNKey sign:]");

    key = [ZNKey keyWithSecret:@"fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140".hexToData
           compressed:YES];
    d = [@"Equations are more important to me, because politics is for the present, but an equation is something for "
         "eternity." dataUsingEncoding:NSUTF8StringEncoding].SHA256;
    sig = [key sign:d];

    XCTAssertEqualObjects(sig, @"3044022054c4a33c6423d689378f160a7ff8b61330444abb58fb470f96ea16d99d4a2fed02200708230441"
                          "0efa6b2943111b6a4e0aaa7b7db55a07e9861d1fb3cb1f421044a5".hexToData, @"[ZNKey sign:]");

    key = [ZNKey keyWithSecret:@"fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140".hexToData
           compressed:YES];
    d = [@"Not only is the Universe stranger than we think, it is stranger than we can think."
         dataUsingEncoding:NSUTF8StringEncoding].SHA256;
    sig = [key sign:d];

    XCTAssertEqualObjects(sig, @"3045022100ff466a9f1b7b273e2f4c3ffe032eb2e814121ed18ef84665d0f515360dab3dd002206fc95f51"
                          "32e5ecfdc8e5e6e616cc77151455d46ed48f5589b7db7771a332b283".hexToData, @"[ZNKey sign:]");

    key = [ZNKey keyWithSecret:@"0000000000000000000000000000000000000000000000000000000000000001".hexToData
           compressed:YES];
    d = [@"How wonderful that we have met with a paradox. Now we have some hope of making progress."
         dataUsingEncoding:NSUTF8StringEncoding].SHA256;
    sig = [key sign:d];

    XCTAssertEqualObjects(sig, @"3045022100c0dafec8251f1d5010289d210232220b03202cba34ec11fec58b3e93a85b91d3022075afdc06"
                          "b7d6322a590955bf264e7aaa155847f614d80078a90292fe205064d3".hexToData, @"[ZNKey sign:]");

    key = [ZNKey keyWithSecret:@"69ec59eaa1f4f2e36b639716b7c30ca86d9a5375c7b38d8918bd9c0ebc80ba64".hexToData
           compressed:YES];
    d = [@"Computer science is no more about computers than astronomy is about telescopes."
         dataUsingEncoding:NSUTF8StringEncoding].SHA256;
    sig = [key sign:d];

    XCTAssertEqualObjects(sig, @"304402207186363571d65e084e7f02b0b77c3ec44fb1b257dee26274c38c928986fea45d02200de0b38e06"
                          "807e46bda1f1e293f4f6323e854c86d58abdd00c46c16441085df6".hexToData, @"[ZNKey sign:]");

    key = [ZNKey keyWithSecret:@"00000000000000000000000000007246174ab1e92e9149c6e446fe194d072637".hexToData
           compressed:YES];
    d = [@"...if you aren't, at any given time, scandalized by code you wrote five or even three years ago, you're not "
         "learning anywhere near enough" dataUsingEncoding:NSUTF8StringEncoding].SHA256;
    sig = [key sign:d];

    XCTAssertEqualObjects(sig, @"3045022100fbfe5076a15860ba8ed00e75e9bd22e05d230f02a936b653eb55b61c99dda48702200e68880e"
                          "bb0050fe4312b1b1eb0899e1b82da89baa5b895f612619edf34cbd37".hexToData, @"[ZNKey sign:]");

    key = [ZNKey keyWithSecret:@"000000000000000000000000000000000000000000056916d0f9b31dc9b637f3".hexToData
           compressed:YES];
    d = [@"The question of whether computers can think is like the question of whether submarines can swim."
         dataUsingEncoding:NSUTF8StringEncoding].SHA256;
    sig = [key sign:d];

    XCTAssertEqualObjects(sig, @"3045022100cde1302d83f8dd835d89aef803c74a119f561fbaef3eb9129e45f30de86abbf9022006ce643f"
                          "5049ee1f27890467b77a6a8e11ec4661cc38cd8badf90115fbd03cef".hexToData, @"[ZNKey sign:]");
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

#pragma mark - testBIP39Mnemonic

- (void)testBIP39Mnemonic
{
    ZNBIP39Mnemonic *m = [ZNBIP39Mnemonic sharedInstance];
    NSString *s = @"bless cloud wheel regular tiny venue bird web grief security dignity zoo";
    NSData *d, *k;

    XCTAssertFalse([m phraseIsValid:s], @"[ZNMnemonic phraseIsValid:]"); // test correct handling of bad checksum

    d = @"00000000000000000000000000000000".hexToData;
    s = [m encodePhrase:d];
    k = [m deriveKeyFromPhrase:s withPassphrase:@"TREZOR"];
    XCTAssertEqualObjects(d, [m decodePhrase:s], @"[ZNBIP39Mnemonic decodePhrase:]");
    XCTAssertEqualObjects(s, @"abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon "
                          "about", @"[ZNBIP39Mnemonic encodePhrase:]");
    XCTAssertEqualObjects(k, @"c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c9"
                          "2f2cf141630c7a3c4ab7c81b2f001698e7463b04".hexToData,
                          @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");

    d = @"7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f".hexToData;
    s = [m encodePhrase:d];
    k = [m deriveKeyFromPhrase:s withPassphrase:@"TREZOR"];
    XCTAssertEqualObjects(d, [m decodePhrase:s], @"[ZNBIP39Mnemonic decodePhrase:]");
    XCTAssertEqualObjects(s, @"legal winner thank year wave sausage worth useful legal winner thank yellow",
                          @"[ZNBIP39Mnemonic encodePhrase:]");
    XCTAssertEqualObjects(k, @"2e8905819b8723fe2c1d161860e5ee1830318dbf49a83bd451cfb8440c28bd6fa457fe1296106559a3c80937"
                          "a1c1069be3a3a5bd381ee6260e8d9739fce1f607".hexToData,
                          @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");

    d = @"80808080808080808080808080808080".hexToData;
    s = [m encodePhrase:d];
    k = [m deriveKeyFromPhrase:s withPassphrase:@"TREZOR"];
    XCTAssertEqualObjects(d, [m decodePhrase:s], @"[ZNBIP39Mnemonic decodePhrase:]");
    XCTAssertEqualObjects(s, @"letter advice cage absurd amount doctor acoustic avoid letter advice cage above",
                          @"[ZNBIP39Mnemonic encodePhrase:]");
    XCTAssertEqualObjects(k, @"d71de856f81a8acc65e6fc851a38d4d7ec216fd0796d0a6827a3ad6ed5511a30fa280f12eb2e47ed2ac03b5c"
                          "462a0358d18d69fe4f985ec81778c1b370b652a8".hexToData,
                          @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");

    d = @"ffffffffffffffffffffffffffffffff".hexToData;
    s = [m encodePhrase:d];
    k = [m deriveKeyFromPhrase:s withPassphrase:@"TREZOR"];
    XCTAssertEqualObjects(d, [m decodePhrase:s], @"[ZNBIP39Mnemonic decodePhrase:]");
    XCTAssertEqualObjects(s, @"zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong",
                          @"[ZNBIP39Mnemonic encodePhrase:]");
    XCTAssertEqualObjects(k, @"ac27495480225222079d7be181583751e86f571027b0497b5b5d11218e0a8a13332572917f0f8e5a589620c6"
                          "f15b11c61dee327651a14c34e18231052e48c069".hexToData,
                          @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");

    d = @"000000000000000000000000000000000000000000000000".hexToData;
    s = [m encodePhrase:d];
    k = [m deriveKeyFromPhrase:s withPassphrase:@"TREZOR"];
    XCTAssertEqualObjects(d, [m decodePhrase:s], @"[ZNBIP39Mnemonic decodePhrase:]");
    XCTAssertEqualObjects(s, @"abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon "
                          "abandon abandon abandon abandon abandon abandon agent",
                          @"[ZNBIP39Mnemonic encodePhrase:]");
    XCTAssertEqualObjects(k, @"035895f2f481b1b0f01fcf8c289c794660b289981a78f8106447707fdd9666ca06da5a9a565181599b79f53b"
                          "844d8a71dd9f439c52a3d7b3e8a79c906ac845fa".hexToData,
                          @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");

    d = @"7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f".hexToData;
    s = [m encodePhrase:d];
    k = [m deriveKeyFromPhrase:s withPassphrase:@"TREZOR"];
    XCTAssertEqualObjects(d, [m decodePhrase:s], @"[ZNBIP39Mnemonic decodePhrase:]");
    XCTAssertEqualObjects(s, @"legal winner thank year wave sausage worth useful legal winner thank year wave sausage "
                          "worth useful legal will",
                          @"[ZNBIP39Mnemonic encodePhrase:]");
    XCTAssertEqualObjects(k, @"f2b94508732bcbacbcc020faefecfc89feafa6649a5491b8c952cede496c214a0c7b3c392d168748f2d4a612"
                          "bada0753b52a1c7ac53c1e93abd5c6320b9e95dd".hexToData,
                          @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");

    d = @"808080808080808080808080808080808080808080808080".hexToData;
    s = [m encodePhrase:d];
    k = [m deriveKeyFromPhrase:s withPassphrase:@"TREZOR"];
    XCTAssertEqualObjects(d, [m decodePhrase:s], @"[ZNBIP39Mnemonic decodePhrase:]");
    XCTAssertEqualObjects(s, @"letter advice cage absurd amount doctor acoustic avoid letter advice cage absurd amount "
                          "doctor acoustic avoid letter always",
                          @"[ZNBIP39Mnemonic encodePhrase:]");
    XCTAssertEqualObjects(k, @"107d7c02a5aa6f38c58083ff74f04c607c2d2c0ecc55501dadd72d025b751bc27fe913ffb796f841c49b1d33"
                          "b610cf0e91d3aa239027f5e99fe4ce9e5088cd65".hexToData,
                          @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");

    d = @"ffffffffffffffffffffffffffffffffffffffffffffffff".hexToData;
    s = [m encodePhrase:d];
    k = [m deriveKeyFromPhrase:s withPassphrase:@"TREZOR"];
    XCTAssertEqualObjects(d, [m decodePhrase:s], @"[ZNBIP39Mnemonic decodePhrase:]");
    XCTAssertEqualObjects(s, @"zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo when",
                          @"[ZNBIP39Mnemonic encodePhrase:]");
    XCTAssertEqualObjects(k, @"0cd6e5d827bb62eb8fc1e262254223817fd068a74b5b449cc2f667c3f1f985a76379b43348d952e2265b4cd1"
                          "29090758b3e3c2c49103b5051aac2eaeb890a528".hexToData,
                          @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");

    d = @"0000000000000000000000000000000000000000000000000000000000000000".hexToData;
    s = [m encodePhrase:d];
    k = [m deriveKeyFromPhrase:s withPassphrase:@"TREZOR"];
    XCTAssertEqualObjects(d, [m decodePhrase:s], @"[ZNBIP39Mnemonic decodePhrase:]");
    XCTAssertEqualObjects(s, @"abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon "
                          "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon "
                          "abandon art", @"[ZNBIP39Mnemonic encodePhrase:]");
    XCTAssertEqualObjects(k, @"bda85446c68413707090a52022edd26a1c9462295029f2e60cd7c4f2bbd3097170af7a4d73245cafa9c3cca8"
                          "d561a7c3de6f5d4a10be8ed2a5e608d68f92fcc8".hexToData,
                          @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");

    d = @"7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f".hexToData;
    s = [m encodePhrase:d];
    k = [m deriveKeyFromPhrase:s withPassphrase:@"TREZOR"];
    XCTAssertEqualObjects(d, [m decodePhrase:s], @"[ZNBIP39Mnemonic decodePhrase:]");
    XCTAssertEqualObjects(s, @"legal winner thank year wave sausage worth useful legal winner thank year wave sausage "
                          "worth useful legal winner thank year wave sausage worth title",
                          @"[ZNBIP39Mnemonic encodePhrase:]");
    XCTAssertEqualObjects(k, @"bc09fca1804f7e69da93c2f2028eb238c227f2e9dda30cd63699232578480a4021b146ad717fbb7e451ce9eb"
                          "835f43620bf5c514db0f8add49f5d121449d3e87".hexToData,
                          @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");

    d = @"8080808080808080808080808080808080808080808080808080808080808080".hexToData;
    s = [m encodePhrase:d];
    k = [m deriveKeyFromPhrase:s withPassphrase:@"TREZOR"];
    XCTAssertEqualObjects(d, [m decodePhrase:s], @"[ZNBIP39Mnemonic decodePhrase:]");
    XCTAssertEqualObjects(s, @"letter advice cage absurd amount doctor acoustic avoid letter advice cage absurd amount "
                          "doctor acoustic avoid letter advice cage absurd amount doctor acoustic bless",
                          @"[ZNBIP39Mnemonic encodePhrase:]");
    XCTAssertEqualObjects(k, @"c0c519bd0e91a2ed54357d9d1ebef6f5af218a153624cf4f2da911a0ed8f7a09e2ef61af0aca007096df4300"
                          "22f7a2b6fb91661a9589097069720d015e4e982f".hexToData,
                          @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");

    d = @"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff".hexToData;
    s = [m encodePhrase:d];
    k = [m deriveKeyFromPhrase:s withPassphrase:@"TREZOR"];
    XCTAssertEqualObjects(d, [m decodePhrase:s], @"[ZNBIP39Mnemonic decodePhrase:]");
    XCTAssertEqualObjects(s, @"zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo "
                          "zoo vote", @"[ZNBIP39Mnemonic encodePhrase:]");
    XCTAssertEqualObjects(k, @"dd48c104698c30cfe2b6142103248622fb7bb0ff692eebb00089b32d22484e1613912f0a5b694407be899ffd"
                          "31ed3992c456cdf60f5d4564b8ba3f05a69890ad".hexToData,
                          @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");

    d = @"77c2b00716cec7213839159e404db50d".hexToData;
    s = [m encodePhrase:d];
    k = [m deriveKeyFromPhrase:s withPassphrase:@"TREZOR"];
    XCTAssertEqualObjects(d, [m decodePhrase:s], @"[ZNBIP39Mnemonic decodePhrase:]");
    XCTAssertEqualObjects(s, @"jelly better achieve collect unaware mountain thought cargo oxygen act hood bridge",
                          @"[ZNBIP39Mnemonic encodePhrase:]");
    XCTAssertEqualObjects(k, @"b5b6d0127db1a9d2226af0c3346031d77af31e918dba64287a1b44b8ebf63cdd52676f672a290aae502472cf"
                          "2d602c051f3e6f18055e84e4c43897fc4e51a6ff".hexToData,
                          @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");

    d = @"b63a9c59a6e641f288ebc103017f1da9f8290b3da6bdef7b".hexToData;
    s = [m encodePhrase:d];
    k = [m deriveKeyFromPhrase:s withPassphrase:@"TREZOR"];
    XCTAssertEqualObjects(d, [m decodePhrase:s], @"[ZNBIP39Mnemonic decodePhrase:]");
    XCTAssertEqualObjects(s, @"renew stay biology evidence goat welcome casual join adapt armor shuffle fault little "
                          "machine walk stumble urge swap",
                          @"[ZNBIP39Mnemonic encodePhrase:]");
    XCTAssertEqualObjects(k, @"9248d83e06f4cd98debf5b6f010542760df925ce46cf38a1bdb4e4de7d21f5c39366941c69e1bdbf2966e0f6"
                          "e6dbece898a0e2f0a4c2b3e640953dfe8b7bbdc5".hexToData,
                          @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");

    d = @"3e141609b97933b66a060dcddc71fad1d91677db872031e85f4c015c5e7e8982".hexToData;
    s = [m encodePhrase:d];
    k = [m deriveKeyFromPhrase:s withPassphrase:@"TREZOR"];
    XCTAssertEqualObjects(d, [m decodePhrase:s], @"[ZNBIP39Mnemonic decodePhrase:]");
    XCTAssertEqualObjects(s, @"dignity pass list indicate nasty swamp pool script soccer toe leaf photo multiply desk "
                          "host tomato cradle drill spread actor shine dismiss champion exotic",
                          @"[ZNBIP39Mnemonic encodePhrase:]");
    XCTAssertEqualObjects(k, @"ff7f3184df8696d8bef94b6c03114dbee0ef89ff938712301d27ed8336ca89ef9635da20af07d4175f2bf5f3"
                          "de130f39c9d9e8dd0472489c19b1a020a940da67".hexToData,
                          @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");

    d = @"0460ef47585604c5660618db2e6a7e7f".hexToData;
    s = [m encodePhrase:d];
    k = [m deriveKeyFromPhrase:s withPassphrase:@"TREZOR"];
    XCTAssertEqualObjects(d, [m decodePhrase:s], @"[ZNBIP39Mnemonic decodePhrase:]");
    XCTAssertEqualObjects(s, @"afford alter spike radar gate glance object seek swamp infant panel yellow",
                          @"[ZNBIP39Mnemonic encodePhrase:]");
    XCTAssertEqualObjects(k, @"65f93a9f36b6c85cbe634ffc1f99f2b82cbb10b31edc7f087b4f6cb9e976e9faf76ff41f8f27c99afdf38f7a"
                          "303ba1136ee48a4c1e7fcd3dba7aa876113a36e4".hexToData,
                          @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");

    d = @"72f60ebac5dd8add8d2a25a797102c3ce21bc029c200076f".hexToData;
    s = [m encodePhrase:d];
    k = [m deriveKeyFromPhrase:s withPassphrase:@"TREZOR"];
    XCTAssertEqualObjects(d, [m decodePhrase:s], @"[ZNBIP39Mnemonic decodePhrase:]");
    XCTAssertEqualObjects(s, @"indicate race push merry suffer human cruise dwarf pole review arch keep canvas theme "
                          "poem divorce alter left",
                          @"[ZNBIP39Mnemonic encodePhrase:]");
    XCTAssertEqualObjects(k, @"3bbf9daa0dfad8229786ace5ddb4e00fa98a044ae4c4975ffd5e094dba9e0bb289349dbe2091761f30f382d4"
                          "e35c4a670ee8ab50758d2c55881be69e327117ba".hexToData,
                          @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");

    d = @"2c85efc7f24ee4573d2b81a6ec66cee209b2dcbd09d8eddc51e0215b0b68e416".hexToData;
    s = [m encodePhrase:d];
    k = [m deriveKeyFromPhrase:s withPassphrase:@"TREZOR"];
    XCTAssertEqualObjects(d, [m decodePhrase:s], @"[ZNBIP39Mnemonic decodePhrase:]");
    XCTAssertEqualObjects(s, @"clutch control vehicle tonight unusual clog visa ice plunge glimpse recipe series open "
                          "hour vintage deposit universe tip job dress radar refuse motion taste",
                          @"[ZNBIP39Mnemonic encodePhrase:]");
    XCTAssertEqualObjects(k, @"fe908f96f46668b2d5b37d82f558c77ed0d69dd0e7e043a5b0511c48c2f1064694a956f86360c93dd04052a8"
                          "899497ce9e985ebe0c8c52b955e6ae86d4ff4449".hexToData,
                          @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");

    d = @"eaebabb2383351fd31d703840b32e9e2".hexToData;
    s = [m encodePhrase:d];
    k = [m deriveKeyFromPhrase:s withPassphrase:@"TREZOR"];
    XCTAssertEqualObjects(d, [m decodePhrase:s], @"[ZNBIP39Mnemonic decodePhrase:]");
    XCTAssertEqualObjects(s, @"turtle front uncle idea crush write shrug there lottery flower risk shell",
                          @"[ZNBIP39Mnemonic encodePhrase:]");
    XCTAssertEqualObjects(k, @"bdfb76a0759f301b0b899a1e3985227e53b3f51e67e3f2a65363caedf3e32fde42a66c404f18d7b05818c95e"
                          "f3ca1e5146646856c461c073169467511680876c".hexToData,
                          @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");

    d = @"7ac45cfe7722ee6c7ba84fbc2d5bd61b45cb2fe5eb65aa78".hexToData;
    s = [m encodePhrase:d];
    k = [m deriveKeyFromPhrase:s withPassphrase:@"TREZOR"];
    XCTAssertEqualObjects(d, [m decodePhrase:s], @"[ZNBIP39Mnemonic decodePhrase:]");
    XCTAssertEqualObjects(s, @"kiss carry display unusual confirm curtain upgrade antique rotate hello void custom "
                          "frequent obey nut hole price segment", @"[ZNBIP39Mnemonic encodePhrase:]");
    XCTAssertEqualObjects(k, @"ed56ff6c833c07982eb7119a8f48fd363c4a9b1601cd2de736b01045c5eb8ab4f57b079403485d1c4924f079"
                          "0dc10a971763337cb9f9c62226f64fff26397c79".hexToData,
                          @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");

    d = @"4fa1a8bc3e6d80ee1316050e862c1812031493212b7ec3f3bb1b08f168cabeef".hexToData;
    s = [m encodePhrase:d];
    k = [m deriveKeyFromPhrase:s withPassphrase:@"TREZOR"];
    XCTAssertEqualObjects(d, [m decodePhrase:s], @"[ZNBIP39Mnemonic decodePhrase:]");
    XCTAssertEqualObjects(s, @"exile ask congress lamp submit jacket era scheme attend cousin alcohol catch course end "
                          "lucky hurt sentence oven short ball bird grab wing top", @"[ZNBIP39Mnemonic encodePhrase:]");
    XCTAssertEqualObjects(k, @"095ee6f817b4c2cb30a5a797360a81a40ab0f9a4e25ecd672a3f58a0b5ba0687c096a6b14d2c0deb3bdefce4"
                          "f61d01ae07417d502429352e27695163f7447a8c".hexToData,
                          @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");

    d = @"18ab19a9f54a9274f03e5209a2ac8a91".hexToData;
    s = [m encodePhrase:d];
    k = [m deriveKeyFromPhrase:s withPassphrase:@"TREZOR"];
    XCTAssertEqualObjects(d, [m decodePhrase:s], @"[ZNBIP39Mnemonic decodePhrase:]");
    XCTAssertEqualObjects(s, @"board flee heavy tunnel powder denial science ski answer betray cargo cat",
                          @"[ZNBIP39Mnemonic encodePhrase:]");
    XCTAssertEqualObjects(k, @"6eff1bb21562918509c73cb990260db07c0ce34ff0e3cc4a8cb3276129fbcb300bddfe005831350efd633909"
                          "f476c45c88253276d9fd0df6ef48609e8bb7dca8".hexToData,
                          @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");

    d = @"18a2e1d81b8ecfb2a333adcb0c17a5b9eb76cc5d05db91a4".hexToData;
    s = [m encodePhrase:d];
    k = [m deriveKeyFromPhrase:s withPassphrase:@"TREZOR"];
    XCTAssertEqualObjects(d, [m decodePhrase:s], @"[ZNBIP39Mnemonic decodePhrase:]");
    XCTAssertEqualObjects(s, @"board blade invite damage undo sun mimic interest slam gaze truly inherit resist great "
                          "inject rocket museum chief", @"[ZNBIP39Mnemonic encodePhrase:]");
    XCTAssertEqualObjects(k, @"f84521c777a13b61564234bf8f8b62b3afce27fc4062b51bb5e62bdfecb23864ee6ecf07c1d5a97c0834307c"
                          "5c852d8ceb88e7c97923c0a3b496bedd4e5f88a9".hexToData,
                          @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");

    d = @"15da872c95a13dd738fbf50e427583ad61f18fd99f628c417a61cf8343c90419".hexToData;
    s = [m encodePhrase:d];
    k = [m deriveKeyFromPhrase:s withPassphrase:@"TREZOR"];
    XCTAssertEqualObjects(d, [m decodePhrase:s], @"[ZNBIP39Mnemonic decodePhrase:]");
    XCTAssertEqualObjects(s, @"beyond stage sleep clip because twist token leaf atom beauty genius food business side "
                          "grid unable middle armed observe pair crouch tonight away coconut",
                          @"[ZNBIP39Mnemonic encodePhrase:]");
    XCTAssertEqualObjects(k, @"b15509eaa2d09d3efd3e006ef42151b30367dc6e3aa5e44caba3fe4d3e352e65101fbdb86a96776b91946ff0"
                          "6f8eac594dc6ee1d3e82a42dfe1b40fef6bcc3fd".hexToData,
                          @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");

    NSString *words_nfkd = @"Pr\u030ci\u0301s\u030cerne\u030c z\u030clut\u030couc\u030cky\u0301 ku\u030an\u030c "
                           "u\u0301pe\u030cl d\u030ca\u0301belske\u0301 o\u0301dy za\u0301ker\u030cny\u0301 "
                           "uc\u030cen\u030c be\u030cz\u030ci\u0301 pode\u0301l zo\u0301ny u\u0301lu\u030a";
    NSString *words_nfc = @"P\u0159\u00ed\u0161ern\u011b \u017elu\u0165ou\u010dk\u00fd k\u016f\u0148 \u00fap\u011bl "
                          "\u010f\u00e1belsk\u00e9 \u00f3dy z\u00e1ke\u0159n\u00fd u\u010de\u0148 b\u011b\u017e\u00ed "
                          "pod\u00e9l z\u00f3ny \u00fal\u016f";
    NSString *words_nfkc = @"P\u0159\u00ed\u0161ern\u011b \u017elu\u0165ou\u010dk\u00fd k\u016f\u0148 \u00fap\u011bl "
                           "\u010f\u00e1belsk\u00e9 \u00f3dy z\u00e1ke\u0159n\u00fd u\u010de\u0148 b\u011b\u017e\u00ed "
                           "pod\u00e9l z\u00f3ny \u00fal\u016f";
    NSString *words_nfd = @"Pr\u030ci\u0301s\u030cerne\u030c z\u030clut\u030couc\u030cky\u0301 ku\u030an\u030c "
                          "u\u0301pe\u030cl d\u030ca\u0301belske\u0301 o\u0301dy za\u0301ker\u030cny\u0301 "
                          "uc\u030cen\u030c be\u030cz\u030ci\u0301 pode\u0301l zo\u0301ny u\u0301lu\u030a";
    NSString *passphrase_nfkd = @"Neuve\u030cr\u030citelne\u030c bezpec\u030cne\u0301 hesli\u0301c\u030cko";
    NSString *passphrase_nfc = @"Neuv\u011b\u0159iteln\u011b bezpe\u010dn\u00e9 hesl\u00ed\u010dko";
    NSString *passphrase_nfkc = @"Neuv\u011b\u0159iteln\u011b bezpe\u010dn\u00e9 hesl\u00ed\u010dko";
    NSString *passphrase_nfd = @"Neuve\u030cr\u030citelne\u030c bezpec\u030cne\u0301 hesli\u0301c\u030cko";
    NSData *seed_nfkd = [m deriveKeyFromPhrase:words_nfkd withPassphrase:passphrase_nfkd];
    NSData *seed_nfc = [m deriveKeyFromPhrase:words_nfc withPassphrase:passphrase_nfc];
    NSData *seed_nfkc = [m deriveKeyFromPhrase:words_nfkc withPassphrase:passphrase_nfkc];
    NSData *seed_nfd = [m deriveKeyFromPhrase:words_nfd withPassphrase:passphrase_nfd];

    // test multiple different unicode representations of the same phrase
    XCTAssertEqualObjects(seed_nfkd, seed_nfc, @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");
    XCTAssertEqualObjects(seed_nfkd, seed_nfkc, @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");
    XCTAssertEqualObjects(seed_nfkd, seed_nfd, @"[ZNBIP39Mnemonic deriveKeyFromPhrase: withPassphrase:]");
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

#if ! BITCOIN_TESTNET
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
#endif

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
    XCTAssertEqualObjects(addr, @"1FHsTashEBUNPQwC1CwVjnKUxzwgw73pU4", @"[[ZNKey keyWithPublicKey:] address]");
#endif
}

#if ! BITCOIN_TESTNET
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
#endif

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
