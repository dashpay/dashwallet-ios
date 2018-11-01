//
//  DWVersionManager.m
//  dashwallet
//
//  Created by Sam Westrich on 11/2/18.
//  Copyright © 2018 Dash Core. All rights reserved.
//

#import "DWVersionManager.h"

#define IDEO_SP   @"\xE3\x80\x80" // ideographic space (utf-8)

@interface DWVersionManager()

@property (nonatomic, strong) id seedObserver;

@end


@implementation DWVersionManager

+ (instancetype)sharedInstance
{
    static id singleton = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        singleton = [self new];
    });
    
    return singleton;
}

-(instancetype)init {
    if (!(self = [super init])) return nil;
self.seedObserver =
[[NSNotificationCenter defaultCenter] addObserverForName:DSChainWalletsDidChangeNotification object:nil
                                                   queue:nil usingBlock:^(NSNotification *note) {
                                                       DSWallet * wallet = [DWEnvironment sharedInstance].currentWallet;
                                                       if (wallet) {
                                                       setKeychainInt(1, SHOWED_WARNING_FOR_INCOMPLETE_PASSPHRASE, NO);
                                                       }
                                                   }];
    return self;
}

- (void)dealloc
{
    if (self.seedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.seedObserver];
}

// There was an issue with passphrases not showing correctly on iPhone 5s and also on devices in Japanese
// (^CheckPassphraseCompletionBlock)(BOOL needsCheck,BOOL authenticated,BOOL cancelled,NSString * _Nullable seedPhrase)
-(void)checkPassphraseWasShownCorrectlyForWallet:(DSWallet*)wallet withCompletion:(CheckPassphraseCompletionBlock)completion
{
    DSAuthenticationManager * authenticationManager = [DSAuthenticationManager sharedInstance];
    NSTimeInterval seedCreationTime = wallet.walletCreationTime + NSTimeIntervalSince1970;
    NSError * error = nil;
    BOOL showedWarningForPassphrase = getKeychainInt(SHOWED_WARNING_FOR_INCOMPLETE_PASSPHRASE, &error);
    if (seedCreationTime < 1534266000 || showedWarningForPassphrase) {
        completion(NO,NO,NO,nil);
        return;
    }
    NSString *language = NSBundle.mainBundle.preferredLocalizations.firstObject;
    CGRect screenRect = [[UIScreen mainScreen] bounds];
    
    [authenticationManager authenticateWithPrompt:(NSLocalizedString(@"Please enter pin to upgrade wallet", nil)) andTouchId:NO alertIfLockout:NO completion:^(BOOL authenticated,BOOL cancelled) {
        if (!authenticated) {
            completion(YES,NO,cancelled,nil);
            return;
        }
        @autoreleasepool {
            NSString * seedPhrase = wallet.seedPhraseIfAuthenticated;
            if (!seedPhrase) {
                setKeychainInt(1, SHOWED_WARNING_FOR_INCOMPLETE_PASSPHRASE, NO);
                completion(YES,YES,NO,seedPhrase);
                return;
            }
            
            NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
            paragraphStyle.lineSpacing = 20;
            paragraphStyle.alignment = NSTextAlignmentCenter;
            NSInteger fontSize = 16;
            NSDictionary * attributes = @{NSFontAttributeName:[UIFont systemFontOfSize:fontSize weight:UIFontWeightMedium],NSForegroundColorAttributeName:[UIColor whiteColor],NSParagraphStyleAttributeName:paragraphStyle};
            
            if (seedPhrase.length > 0 && [seedPhrase characterAtIndex:0] > 0x3000) { // ideographic language
                NSInteger lineCount = 1;
                NSMutableString *s,*l;
                
                CGRect r;
                s = CFBridgingRelease(CFStringCreateMutable(SecureAllocator(), 0)),
                l = CFBridgingRelease(CFStringCreateMutable(SecureAllocator(), 0));
                for (NSString *w in CFBridgingRelease(CFStringCreateArrayBySeparatingStrings(SecureAllocator(),
                                                                                             (CFStringRef)seedPhrase, CFSTR(" ")))) {
                    if (l.length > 0) [l appendString:IDEO_SP];
                    [l appendString:w];
                    r = [l boundingRectWithSize:CGRectInfinite.size options:NSStringDrawingUsesLineFragmentOrigin
                                     attributes:@{NSFontAttributeName:[UIFont systemFontOfSize:fontSize weight:UIFontWeightMedium]} context:nil];
                    
                    if (r.size.width >= screenRect.size.width - 54*2 - 16) {
                        [s appendString:@"\n"];
                        l.string = w;
                        lineCount++;
                    }
                    else if (s.length > 0) [s appendString:IDEO_SP];
                    
                    [s appendString:w];
                }
                if (lineCount > 3) {
                    setKeychainInt(1, SHOWED_WARNING_FOR_INCOMPLETE_PASSPHRASE, NO);
                    completion(YES,YES,NO,seedPhrase);
                    return;
                }
            }
            
            else {
                NSInteger lineCount = 0;
                
                attributes = @{NSFontAttributeName:[UIFont systemFontOfSize:fontSize weight:UIFontWeightMedium],NSForegroundColorAttributeName:[UIColor whiteColor],NSParagraphStyleAttributeName:paragraphStyle};
                CGSize labelSize = (CGSize){screenRect.size.width - 54*2 - 16, MAXFLOAT};
                CGRect requiredSize = [seedPhrase boundingRectWithSize:labelSize  options:NSStringDrawingUsesLineFragmentOrigin attributes:attributes context:nil];
                long charSize = lroundf(((UIFont*)attributes[NSFontAttributeName]).lineHeight + 12);
                long rHeight = lroundf(requiredSize.size.height);
                lineCount = rHeight/charSize;
                
                if (lineCount > 3) {
                    setKeychainInt(1, SHOWED_WARNING_FOR_INCOMPLETE_PASSPHRASE, NO);
                    completion(YES,YES,NO,seedPhrase);
                    return;
                    
                }
                
            }
            setKeychainInt(1, SHOWED_WARNING_FOR_INCOMPLETE_PASSPHRASE, NO);
            completion(NO,YES,NO,seedPhrase);
            
        }
    }];
    
}


@end
