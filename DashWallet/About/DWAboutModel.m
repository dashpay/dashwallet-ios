//  
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

#import "DWAboutModel.h"

#import <arpa/inet.h>
#import <asl.h>
#import <netdb.h>
#import <sys/socket.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DWAboutModel

- (NSString *)mainTitle {
    DWEnvironment *environment = [DWEnvironment sharedInstance];
    NSString *networkString = @"";
    if (![environment.currentChain isMainnet]) {
        networkString = [NSString stringWithFormat:@" (%@)", environment.currentChain.name];
    }
    
    static NSString *dashSyncCommit = nil;
    if (!dashSyncCommit) {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"DashSyncCurrentCommit" ofType:nil];
        dashSyncCommit = [[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        NSParameterAssert(dashSyncCommit);
        if (!dashSyncCommit) {
            dashSyncCommit = @"?";
        }
        // use first 7 characters of commit sha (same as GitHub)
        dashSyncCommit = dashSyncCommit.length > 7 ? [dashSyncCommit substringToIndex:7] : dashSyncCommit;
    }
    
    NSBundle *bundle = [NSBundle mainBundle];
    // non-localizable
    return [NSString stringWithFormat:@"DashWallet v%@ - %@%@\nDashSync %@",
            bundle.infoDictionary[@"CFBundleShortVersionString"],
            bundle.infoDictionary[@"CFBundleVersion"],
            networkString,
            dashSyncCommit];
}

- (NSString *)status {
    static NSDateFormatter *dateFormatter = nil;
    if (!dateFormatter) {
        dateFormatter = [NSDateFormatter new];
        dateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"Mdjma" options:0 locale:[NSLocale currentLocale]];
    }
    
    DSAuthenticationManager *authenticationManager = [DSAuthenticationManager sharedInstance];
    DSPriceManager *priceManager = [DSPriceManager sharedInstance];
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    DSPeerManager *peerManager = [DWEnvironment sharedInstance].currentChainManager.peerManager;
    DSMasternodeManager *masternodeManager = [DWEnvironment sharedInstance].currentChainManager.masternodeManager;
    DSMasternodeList *currentMasternodeList = masternodeManager.currentMasternodeList;
    
    
    return [NSString stringWithFormat:NSLocalizedString(@"rate: %@ = %@\nupdated: %@\nblock #%d of %d\n"
                                                        "connected peers: %d\ndl peer: %@\nquorums validated: %d/%d",
                                                        NULL),
            [priceManager localCurrencyStringForDashAmount:DUFFS / priceManager.localCurrencyDashPrice.doubleValue],
            [priceManager stringForDashAmount:DUFFS / priceManager.localCurrencyDashPrice.doubleValue],
            [dateFormatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:authenticationManager.secureTime]].lowercaseString,
            chain.lastBlockHeight,
            chain.estimatedBlockHeight,
            peerManager.connectedPeerCount,
            peerManager.downloadPeerName?peerManager.downloadPeerName:@"-",
            [currentMasternodeList validQuorumsCountOfType:DSLLMQType_50_60],
            [currentMasternodeList quorumsCountOfType:DSLLMQType_50_60]];
}

- (void)performCopyLogs {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    
    [DSEventManager saveEvent:@"settings:copy_logs"];
    aslmsg q = asl_new(ASL_TYPE_QUERY), m;
    aslresponse r = asl_search(NULL, q);
    NSMutableString *s = [NSMutableString string];
    time_t t;
    struct tm tm;
    
    while ((m = asl_next(r))) {
        t = strtol(asl_get(m, ASL_KEY_TIME), NULL, 10);
        localtime_r(&t, &tm);
        [s appendFormat:@"%d-%02d-%02d %02d:%02d:%02d %s: %s\n",
         tm.tm_year + 1900,
         tm.tm_mon,
         tm.tm_mday,
         tm.tm_hour,
         tm.tm_min,
         tm.tm_sec,
         asl_get(m, ASL_KEY_SENDER),
         asl_get(m, ASL_KEY_MSG)];
    }
    
    asl_free(r);
    [UIPasteboard generalPasteboard].string = (s.length < 8000000) ? s : [s substringFromIndex:s.length - 8000000];
    
#pragma GCC diagnostic pop
}

- (void)setFixedPeer:(NSString *)fixedPeer {
    NSArray *pair = [fixedPeer componentsSeparatedByString:@":"];
    NSString *host = pair.firstObject;
    NSString *service = (pair.count > 1) ? pair[1] : @([DWEnvironment sharedInstance].currentChain.standardPort).stringValue;
    struct addrinfo hints = {0, AF_UNSPEC, SOCK_STREAM, 0, 0, 0, NULL, NULL}, *servinfo, *p;
    UInt128 addr = {.u32 = {0, 0, CFSwapInt32HostToBig(0xffff), 0}};
    
    NSLog(@"DNS lookup %@", host);
    
    if (getaddrinfo(host.UTF8String, service.UTF8String, &hints, &servinfo) == 0) {
        for (p = servinfo; p != NULL; p = p->ai_next) {
            if (p->ai_family == AF_INET) {
                addr.u64[0] = 0;
                addr.u32[2] = CFSwapInt32HostToBig(0xffff);
                addr.u32[3] = ((struct sockaddr_in *)p->ai_addr)->sin_addr.s_addr;
            }
            //                else if (p->ai_family == AF_INET6) {
            //                    addr = *(UInt128 *)&((struct sockaddr_in6 *)p->ai_addr)->sin6_addr;
            //                }
            else {
                continue;
            }
            
            uint16_t port = CFSwapInt16BigToHost(((struct sockaddr_in *)p->ai_addr)->sin_port);
            char s[INET6_ADDRSTRLEN];
            
            if (addr.u64[0] == 0 && addr.u32[2] == CFSwapInt32HostToBig(0xffff)) {
                host = @(inet_ntop(AF_INET, &addr.u32[3], s, sizeof(s)));
            }
            else {
                host = @(inet_ntop(AF_INET6, &addr, s, sizeof(s)));
            }
            [[DWEnvironment sharedInstance].currentChainManager.peerManager setTrustedPeerHost:[NSString stringWithFormat:@"%@:%d", host, port]];
            [[DWEnvironment sharedInstance].currentChainManager.peerManager disconnect];
            [[DWEnvironment sharedInstance].currentChainManager.peerManager connect];
            break;
        }
        
        freeaddrinfo(servinfo);
    }
}

- (void)clearFixedPeer {
    DSPeerManager * peerManager = [DWEnvironment sharedInstance].currentChainManager.peerManager;
    [peerManager removeTrustedPeerHost];
    [peerManager disconnect];
    [peerManager connect];
}

@end

NS_ASSUME_NONNULL_END
