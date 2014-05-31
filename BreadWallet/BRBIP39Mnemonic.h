//
//  BRBIP39Mnemonic.h
//  BreadWallet
//
//  Created by Aaron Voisine on 3/21/14.
//  Copyright (c) 2014 Aaron Voisine <voisine@gmail.com>
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

#import <Foundation/Foundation.h>
#import "BRMnemonic.h"

// BIP39 is method for generating a deterministic wallet seed from a mnemonic phrase
// https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki

@interface BRBIP39Mnemonic : NSObject<BRMnemonic>

+ (instancetype)sharedInstance;

- (NSString *)encodePhrase:(NSData *)data;
- (NSData *)decodePhrase:(NSString *)phrase;

- (BOOL)phraseIsValid:(NSString *)phrase;
- (NSData *)deriveKeyFromPhrase:(NSString *)phrase withPassphrase:(NSString *)passphrase;

@end
