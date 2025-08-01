//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#include "DashWallet-Prefix.pch"

#if SNAPSHOT
static const bool _SNAPSHOT = 1;
#else
static const bool _SNAPSHOT = 0;
#endif /* SNAPSHOT */

//MARK: DashSync
#import <DashSync/DSLogger.h>
#import "DSTransaction.h"
#import "DSCoinbaseTransaction.h"
#import "DSWallet.h"
#import "DSReachabilityManager.h"
#import "DSCurrencyPriceObject.h"
#import "DSPriceOperationProvider.h"
#import "DSOperation.h"
#import "DSOperationQueue.h"
#import "DSDerivationPathFactory.h"
#import "DSKeyManager.h"
#import "BigIntTypes.h"
#import "NSString+Dash.h"
#import "DSChainManager.h"
#import "DSChain.h"

//MARK: DashWallet
#import "DWEnvironment.h"
#import "DWTitleDetailCellModel.h"
#import "DWTitleDetailItem.h"
#import "DWGlobalOptions.h"
#import "DWUIKit.h"
#import "DWAboutModel.h"
#import "DWBaseActionButtonViewController.h"
#import "DWNumberKeyboardInputViewAudioFeedback.h"
#import "DWInputValidator.h"
#import "DWAmountInputValidator.h"
#import "DWLocalCurrencyViewController.h"
#import "DWDemoDelegate.h"
#import "DWModalPopupTransition.h"
#import "DWModalTransition.h"
#import "UIView+DWHUD.h"
#import "UIView+DWAnimations.h"
#import "UIViewController+KeyboardAdditions.h"
#import "SFSafariViewController+DashWallet.h"
#import "UIFont+DWFont.h"
#import "NSData+Dash.h"
#import "CALayer+DWShadow.h"
#import "DSTransaction+DashWallet.h"
#import "DWAlertController.h"
#import "DWHomeProtocol.h"
#import "UIDevice+DashWallet.h"
#import "DWCenteredTableView.h"
#import "DWHomeModelStub.h"

//MARK: Backup Wallet
#import "DWPreviewSeedPhraseViewController.h"
#import "DWSecureWalletDelegate.h"
#import "DWPreviewSeedPhraseContentView.h"
#import "DWPreviewSeedPhraseViewController+DWProtected.h"
#import "DWVerifySeedPhraseViewController.h"

//MARK: Payment flow
#import "DWQRScanModel.h"
#import "DWPayOptionModel.h"
#import "DWPayModelProtocol.h"
#import "DWReceiveModelProtocol.h"
#import "DWReceiveModel.h"
#import "DWTransactionListDataProviderProtocol.h"
#import "DWQuickReceiveViewController.h"
#import "DWQRScanViewController.h"
#import "DWRequestAmountViewController.h"
#import "UIViewController+DWShareReceiveInfo.h"
#import "DWImportWalletInfoViewController.h"
#import "DWPaymentProcessor.h"
#import "DWPaymentOutput.h"
#import "DWPaymentOutput+DWView.h"
#import "DWPaymentInput.h"
#import "DWPaymentInputBuilder.h"

//MARK: Uphold
#import "DWUpholdTransactionObject.h"
#import "DWUpholdTransactionObject+DWView.h"
#import "DWUpholdClient.h"
#import "DWUpholdCardObject.h"
#import "DWUpholdOTPViewController.h"
#import "DWUpholdOTPProvider.h"
#import "DWUpholdClientCancellationToken.h"
#import "DWUpholdLogoutTutorialViewController.h"
#import "DWUpholdConstants.h"

//MARK: 3rd Party
#import <SDWebImage/SDWebImage.h>
#import "DWPhoneWCSessionManager.h"

//MARK: DashPay
#import "DWDPBasicUserItem.h"
#import "DWDPAvatarView.h"
#import "DWDPRegistrationStatus.h"
#import "DWDPUserObject.h"
#import "DWModalUserProfileViewController.h"
#import "DWInvitationActionsView.h"
#import "DWInvitationPreviewViewController.h"
#import "DWInvitationLinkBuilder.h"
#import "DWSuccessInvitationView.h"
#import "DWInvitationMessageView.h"
#import "DWScrollingViewController.h"
#import "UIView+DWEmbedding.h"
#import "DWBasePressableControl.h"

#if DASHPAY
#import "DWInvitationSetupState.h"
#import "DPAlertViewController.h"
#import "DWNotificationsViewController.h"
#import "DWDashPayConstants.h"
#import "DWRootContactsViewController.h"
#import "DWNotificationsProvider.h"
#import "DWContactsViewController.h"
#import "DWCreateUsernameViewController.h"
#import "DWConfirmUsernameViewController.h"
#import "DWUsernamePendingViewController.h"
#import "DWRegistrationCompletedViewController.h"
#import "DWUsernameHeaderView.h"
#import "DWContainerViewController.h"
#import "DWDashPaySetupModel.h"
#import "UIViewController+DWDisplayError.h"
#import "DWEditProfileViewController.h"
#import "DWSaveAlertViewController.h"
#import "DWDPWelcomeCollectionViewController.h"
#import "DWGetStarted.h"
#import "DWGetStartedContentViewController.h"
#import "DWDashPayContactsUpdater.h"
#import "DWDPUpdateProfileModel.h"
#import "DWInvitationHistoryViewController.h"
#endif

//MARK: CrowdNode
#import "DWCheckbox.h"
#import "DWPreviewSeedPhraseModel.h"
#import "DWSeedPhraseModel.h"
#import "UIImage+Utils.h"
#import "NSData+Dash.h"
#import "DSChain+DashWallet.h"

//MARK: Tabbar
#import "DWWipeDelegate.h"
#import "DWPayModel.h"

//MARK: Home
#import "DWHomeModel.h"
#import "DWRecoverViewController.h"
#import "DSAuthenticationManager.h"
#import "DSAuthenticationManager+Private.h"
#import "DWSecureWalletDelegate.h"
#import "DWBasePayViewController.h"
#import "DWHomeProtocol.h"

//MARK: Settings menu
#import "UIViewController+DWDisplayError.h"
#import "DWFormTableViewController.h"
#import "DWAboutViewController.h"
#import "DWCurrentUserProfileView.h"
#import "DWSharedUIConstants.h"
#import "DWUserProfileContainerView.h"
#import "DWDashPayReadyProtocol.h"
#import "DWSetPinViewController.h"
#import "DWAdvancedSecurityViewController.h"
#import "DWBiometricAuthModel.h"
#import "DWAdvancedSecurityModel.h"
#import "DWResetWalletInfoViewController.h"
#import "DWPreviewSeedPhraseModel.h"
#import "DWPreviewSeedPhraseViewController.h"
#import "DWSecureWalletDelegate.h"
#if SNAPSHOT
#import "DWDemoAdvancedSecurityViewController.h"
#endif

//MARK: Onboarding
#import "DWTransactionStub.h"

//MARK: CoinJoin
#import "DSCoinJoinManager.h"


// TODO
#import "DSInstantSendTransactionLock.h"
