//
//  DSDerivationPathEntity+CoreDataClass.m
//  
//
//  Created by Sam Westrich on 5/20/18.
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

#import "DSDerivationPathEntity+CoreDataClass.h"
#import "DSChainEntity+CoreDataClass.h"
#import "DSChain.h"
#import "DSWallet.h"
#import "DSAccount.h"
#import "DSDerivationPath.h"
#import "NSManagedObject+Sugar.h"
#import "DSBIP39Mnemonic.h"
#import "DSAccountEntity+CoreDataClass.h"

@implementation DSDerivationPathEntity

+ (DSDerivationPathEntity* _Nonnull)derivationPathEntityMatchingDerivationPath:(DSDerivationPath*)derivationPath {
    NSAssert(derivationPath.standaloneExtendedPublicKeyUniqueID, @"standaloneExtendedPublicKeyUniqueID must be set");
    //DSChain * chain = derivationPath.chain;
    NSArray * derivationPathEntities;
    NSData * archivedDerivationPath = [NSKeyedArchiver archivedDataWithRootObject:derivationPath];
    DSChainEntity * chainEntity = derivationPath.chain.chainEntity;
        //NSUInteger count = [chainEntity.derivationPaths count];
        derivationPathEntities = [[chainEntity.derivationPaths objectsPassingTest:^BOOL(DSDerivationPathEntity * _Nonnull obj, BOOL * _Nonnull stop) {
            return ([obj.publicKeyIdentifier isEqualToString:derivationPath.standaloneExtendedPublicKeyUniqueID]);
        }] allObjects];
    
    //&& [obj.derivationPath isEqualToData:archivedDerivationPath]
    if ([derivationPathEntities count]) {
        return [derivationPathEntities firstObject];
    } else {
        DSDerivationPathEntity * derivationPathEntity = [DSDerivationPathEntity managedObject];
        derivationPathEntity.derivationPath = archivedDerivationPath;
        derivationPathEntity.chain = chainEntity;
        derivationPathEntity.publicKeyIdentifier = derivationPath.standaloneExtendedPublicKeyUniqueID;
        derivationPathEntity.syncBlockHeight = BIP39_CREATION_TIME;
        if (derivationPath.account) {
        derivationPathEntity.account = [DSAccountEntity accountEntityForWalletUniqueID:derivationPath.account.wallet.uniqueID index:derivationPath.account.accountNumber];
        }
        return derivationPathEntity;
    }
}

@end
