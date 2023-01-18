//
//  Created by tkhp
//  Copyright © 2023 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "DSBlock.h"
#import "DSChain+DashWallet.h"
#import "DSChainsManager.h"
#import "DSCheckpoint.h"
#import "DSMasternodeManager.h"
#import "NSDate+Utils.h"
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

const double BLOCK_TARGET_SPACING = 2.625 * 60;

static double convertBitsToDouble(uint32_t nBits) {
    long nShift = (nBits >> 24) & 0xff;

    double dDiff =
        (double)0x0000ffff / (double)(nBits & 0x00ffffff);

    while (nShift < 29) {
        dDiff *= 256.0;
        nShift++;
    }
    while (nShift > 29) {
        dDiff /= 256.0;
        nShift--;
    }

    return dDiff;
}

static void *LaserUnicornPropertyKey = &LaserUnicornPropertyKey;

@implementation DSChain (DashWallet)
- (NSNumber *)apy {
    NSNumber *cached = (NSNumber *)objc_getAssociatedObject(self, @selector(apy));

    if (!cached) {
        NSNumber *newApy = [self calculateMasternodeAPY];

        if (!newApy || newApy.doubleValue == INFINITY)
            return [self calculateEstimatedMasternodeAPY];

        self.apy = newApy;
        return newApy;
    }

    return cached;
}

- (void)setApy:(NSNumber *)apyValue {
    objc_setAssociatedObject(self, @selector(apy), apyValue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSNumber *)calculateEstimatedMasternodeAPY {
    const int32_t MASTERNODE_COUNT = 3800;

    DSCheckpoint *checkpoint = self.lastCheckpointHavingMasternodeList;

    NSTimeInterval timeElapsedSinceCheckpoint = [NSDate timeIntervalSince1970] - checkpoint.timestamp;
    uint64_t estimatedBlockHeight = (timeElapsedSinceCheckpoint / BLOCK_TARGET_SPACING) + checkpoint.height;

    DSMasternodeManager *masternodeManager = self.chainManager.masternodeManager;
    DSMasternodeList *list = [masternodeManager masternodeListForBlockHash:checkpoint.blockHash];

    return [self calculateMasternodeAPYWithHeight:estimatedBlockHeight
                             prevDifficultyTarget:checkpoint.target
                                  masternodeCount:MASTERNODE_COUNT];
}

- (NSNumber *_Nullable)calculateMasternodeAPY {
    if (self.lastTerminalBlock.target == 0)
        return nil;

    DSMasternodeList *masternodeList = self.chainManager.masternodeManager.currentMasternodeList;

    if (masternodeList.validMasternodeCount == 0)
        return nil;

    return [self calculateMasternodeAPYWithHeight:self.lastTerminalBlock.height
                             prevDifficultyTarget:self.lastTerminalBlock.target
                                  masternodeCount:masternodeList.validMasternodeCount];
}

- (NSNumber *)calculateMasternodeAPYWithHeight:(uint64_t)height prevDifficultyTarget:(uint32_t)difficulty masternodeCount:(uint64_t)mnCount {

    const double DAYS_PER_YEAR = 365.242199;
    const double SECONDS_PER_DAY = 24 * 60 * 60;

    uint64_t blockReward = [self calculateblockInflationWithHeight:height nPrevBits:difficulty fSuperblockPartOnly:NO];
    uint64_t masternodeReward = [self calculateMasternodePaymentWithHeight:height blockReward:blockReward];

    double blocksPerYear = (DAYS_PER_YEAR * SECONDS_PER_DAY / BLOCK_TARGET_SPACING);
    double payoutsPerYear = blocksPerYear / mnCount;

    return @(100.0 * masternodeReward * payoutsPerYear / MASTERNODE_COST);
}

- (uint64_t)calculateMasternodePaymentWithHeight:(uint64_t)height blockReward:(uint64_t)blockReward {
    const int periods[] = {
        513, // Period 1:  51.3%
        526, // Period 2:  52.6%
        533, // Period 3:  53.3%
        540, // Period 4:  54%
        546, // Period 5:  54.6%
        552, // Period 6:  55.2%
        557, // Period 7:  55.7%
        562, // Period 8:  56.2%
        567, // Period 9:  56.7%
        572, // Period 10: 57.2%
        577, // Period 11: 57.7%
        582, // Period 12: 58.2%
        585, // Period 13: 58.5%
        588, // Period 14: 58.8%
        591, // Period 15: 59.1%
        594, // Period 16: 59.4%
        597, // Period 17: 59.7%
        599, // Period 18: 59.9%
        600  // Period 19: 60%
    };
    int periodsCount = sizeof(periods) / sizeof(int);

    uint64_t ret = blockReward / 5;

    NSUInteger increaseBlockHeight = [self increaseBlockHeight];
    NSUInteger period = [self period];
    NSUInteger brrHeight = [self brrHeight];

    // mainnet:
    if (height > increaseBlockHeight)
        ret = ret + blockReward / 20; // 158000 - 25.0% - 2014-10-24
    if (height > increaseBlockHeight + period)
        ret = ret + blockReward / 20; // 175280 - 30.0% - 2014-11-25
    if (height > increaseBlockHeight + period * 2)
        ret = ret + blockReward / 20; // 192560 - 35.0% - 2014-12-26
    if (height > increaseBlockHeight + period * 3)
        ret = ret + blockReward / 40; // 209840 - 37.5% - 2015-01-26
    if (height > increaseBlockHeight + period * 4)
        ret = ret + blockReward / 40; // 227120 - 40.0% - 2015-02-27
    if (height > increaseBlockHeight + period * 5)
        ret = ret + blockReward / 40; // 244400 - 42.5% - 2015-03-30
    if (height > increaseBlockHeight + period * 6)
        ret = ret + blockReward / 40; // 261680 - 45.0% - 2015-05-01
    if (height > increaseBlockHeight + period * 7)
        ret = ret + blockReward / 40; // 278960 - 47.5% - 2015-06-01
    if (height > increaseBlockHeight + period * 9)
        ret = ret + blockReward / 40; // 313520 - 50.0% - 2015-08-03
    if (height < brrHeight) {
        // Block Reward Realocation is not activated yet, nothing to do
        return ret;
    }

    NSUInteger superblockCycle = [self superblockCycle];
    // Actual reallocation starts in the cycle next to one activation happens in
    long double reallocStart = brrHeight - brrHeight % superblockCycle + superblockCycle;

    if (height < reallocStart) {
        // Activated but we have to wait for the next cycle to start realocation, nothing to do
        return ret;
    }
    NSUInteger reallocCycle = superblockCycle * 3;
    NSUInteger nCurrentPeriod = MIN((height - reallocStart) / reallocCycle, periodsCount - 1);
    return (blockReward * periods[nCurrentPeriod]) / 1000;
}

- (uint64_t)calculateblockInflationWithHeight:(uint64_t)height nPrevBits:(uint32_t)nPrevBits fSuperblockPartOnly:(BOOL)fSuperblockPartOnly {
    double dDiff;
    int64_t nSubsidyBase;
    uint64_t nPrevHeight = height - 1;

    if (nPrevHeight <= 4500 && self.isMainnet) {
        /* a bug which caused diff to not be correctly calculated */
        dDiff = (double)0x0000ffff / (double)(nPrevBits & 0x00ffffff);
    }
    else {
        dDiff = convertBitsToDouble(nPrevBits);
    }

    if (nPrevHeight < 5465) {
        // Early ages...
        // 1111/((x+1)^2)
        nSubsidyBase = (uint64_t)(1111.0 / (pow((dDiff + 1.0), 2.0)));
        if (nSubsidyBase > 500)
            nSubsidyBase = 500;
        else if (nSubsidyBase < 1)
            nSubsidyBase = 1;
    }
    else if (nPrevHeight < 17000 || (dDiff <= 75 && nPrevHeight < 24000)) {
        // CPU mining era
        // 11111/(((x+51)/6)^2)
        nSubsidyBase = (uint64_t)(11111.0 / (pow((dDiff + 51.0) / 6.0, 2.0)));
        if (nSubsidyBase > 500)
            nSubsidyBase = 500;
        else if (nSubsidyBase < 25)
            nSubsidyBase = 25;
    }
    else {
        // GPU/ASIC mining era
        // 2222222/(((x+2600)/9)^2)
        nSubsidyBase = (uint64_t)(2222222.0 / (pow((dDiff + 2600.0) / 9.0, 2.0)));
        if (nSubsidyBase > 25)
            nSubsidyBase = 25;
        else if (nSubsidyBase < 5)
            nSubsidyBase = 5;
    }

    // LogPrintf("height %u diff %4.2f reward %d\n", nPrevHeight, dDiff, nSubsidyBase);
    uint64_t nSubsidy = nSubsidyBase * 100000000;
    uint64_t subsidyDecreaseBlockCount = [self subsidyDecreaseBlockCount];
    // yearly decline of production by ~7.1% per year, projected ~18M coins max by year 2050+.
    for (int i = subsidyDecreaseBlockCount; i <= nPrevHeight; i += subsidyDecreaseBlockCount) {
        nSubsidy = nSubsidy - nSubsidy / 14;
    }

    // Hard fork to reduce the block reward by 10 extra percent (allowing budget/superblocks)
    uint64_t nSuperblockPart = (nPrevHeight > [self budgetPaymentsStartBlock]) ? nSubsidy / 10 : 0;

    return fSuperblockPartOnly ? nSuperblockPart : nSubsidy - nSuperblockPart;
}

- (uint64_t)increaseBlockHeight {
    switch (self.chainType) {
        case DSChainType_MainNet:
            return 158000;
        case DSChainType_TestNet:
            return 4030;
        case DSChainType_DevNet:
            return 4030;
    }
}

- (uint64_t)period {
    switch (self.chainType) {
        case DSChainType_MainNet:
            return 576 * 30;
        case DSChainType_TestNet:
            return 10;
        case DSChainType_DevNet:
            return 10;
    }
}

- (uint64_t)brrHeight {
    switch (self.chainType) {
        case DSChainType_MainNet:
            return 1374912;
        case DSChainType_TestNet:
            return 387500;
        case DSChainType_DevNet:
            return 300;
    }
}

- (uint64_t)superblockCycle {
    switch (self.chainType) {
        case DSChainType_MainNet:
            return 16616;
        case DSChainType_TestNet:
            return 24;
        case DSChainType_DevNet:
            return 24;
    }
}

- (uint64_t)superblockStartBlock {
    switch (self.chainType) {
        case DSChainType_MainNet:
            return 614820;
        case DSChainType_TestNet:
            return 4200;
        case DSChainType_DevNet:
            return 24;
    }
}

- (uint64_t)subsidyDecreaseBlockCount {
    switch (self.chainType) {
        case DSChainType_MainNet:
            return 210240;
        case DSChainType_TestNet:
            return 210240;
        case DSChainType_DevNet:
            return 210240;
    }
}

- (uint64_t)budgetPaymentsStartBlock {
    switch (self.chainType) {
        case DSChainType_MainNet:
            return 328008;
        case DSChainType_TestNet:
            return 4100;
        case DSChainType_DevNet:
            return 4100;
    }
}


@end

NS_ASSUME_NONNULL_END
