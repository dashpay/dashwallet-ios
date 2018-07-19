//
//  DSBIP39Mnemonic.h
//  DashSync
//
//  Created by Aaron Voisine on 3/21/14.
//  Copyright (c) 2014 Aaron Voisine <voisine@gmail.com>
//  Updated by Quantum Explorer on 05/11/18.
//  Copyright (c) 2018 Quantum Explorer <quantum@dash.org>
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
#import "DSMnemonic.h"

// BIP39 is method for generating a deterministic wallet seed from a mnemonic phrase
// https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki

#define BIP39_CREATION_TIME (1427587200.0 - NSTimeIntervalSince1970)

@interface DSBIP39Mnemonic : NSObject<DSMnemonic>

+ (instancetype _Nullable)sharedInstance;

- (NSString *)encodePhrase:(NSData *)data;
- (NSData *)decodePhrase:(NSString *)phrase; // phrase must be normalized
- (BOOL)wordIsValid:(NSString *)word; // true if word is a member of any known word list
- (BOOL)wordIsLocal:(NSString *)word; // true if word is a member of the word list for the current locale
- (BOOL)phraseIsValid:(NSString *)phrase; // true if all words and checksum are valid, phrase must be normalized
- (NSString *)cleanupPhrase:(NSString *)phrase; // minimally cleans up user input phrase, suitable for display/editing
- (NSString *)normalizePhrase:(NSString *)phrase; // normalizes phrase, suitable for decode/derivation
- (NSData *)deriveKeyFromPhrase:(NSString *)phrase withPassphrase:(NSString *)passphrase; // phrase must be normalized

@end
