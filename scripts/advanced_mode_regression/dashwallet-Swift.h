// Foundation-only test substitutes for unrelated keychain/wallet dependencies.
// DWGlobalOptions and DSDynamicOptions themselves are compiled unchanged.
#import <Foundation/Foundation.h>
#define DW_KEYPATH(object, property) @ #property
@interface DWKeychainStore : NSObject
+ (int64_t)int64ForAccount:(NSString *)account;
+ (void)setInt64:(int64_t)value forAccount:(NSString *)account authenticated:(BOOL)authenticated;
@end
@interface DWWalletEnvironment : NSObject
+ (NSString *)activeWalletIdHex;
@end
