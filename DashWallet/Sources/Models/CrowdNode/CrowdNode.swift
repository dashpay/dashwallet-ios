//
//  Created by Andrei Ashikhmin
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

import Combine
import BackgroundTasks

@objc public class CrowdNodeObjcWrapper: NSObject {
    @objc public class func restoreState() {
        CrowdNode.shared.restoreState()
    }
    
    @objc public class func isInterrupted() -> Bool {
        return CrowdNode.shared.signUpState == .acceptTermsRequired
    }
    
    @objc public class func continueInterrupted() {
        let crowdNode = CrowdNode.shared
        
        if crowdNode.signUpState == .acceptTermsRequired {
            Task {
                let address = crowdNode.accountAddress
                await crowdNode.signUp(accountAddress: address)
            }
        }
    }
}

public final class CrowdNode {
    enum SignUpState: Comparable {
        case notInitiated
        case notStarted
        // Create New Account
        case fundingWallet
        case signingUp
        case acceptTermsRequired
        case acceptingTerms
        case finished
        case error
        // Link Existing Account
        case linkedOnline
    }
    
    private var cancellableBag = Set<AnyCancellable>()
    private var syncStateObserver: AnyCancellable?
    private let sendCoinsService = SendCoinsService()
    private let txObserver = TransactionObserver()
    @Published private(set) var signUpState = SignUpState.notInitiated
    
    private(set) var accountAddress: String = ""
    private(set) var apiError: Error?

    public static let shared: CrowdNode = .init()
    
    init() {
        NotificationCenter.default.publisher(for: NSNotification.Name.DWWillWipeWallet)
            .sink { [weak self] _ in self?.reset() }
            .store(in: &cancellableBag)
    }
}

extension CrowdNode {
    func restoreState() {
        if signUpState > SignUpState.notStarted {
            // Already started/restored
            return
        }

        print("restoring CrowdNode state")
        signUpState = SignUpState.notStarted
        let fullSet = FullCrowdNodeSignUpTxSet()
        let wallet = DWEnvironment.sharedInstance().currentWallet
        wallet.allTransactions.forEach { transaction in
            fullSet.tryInclude(tx: transaction)
        }

        if let welcomeResponse = fullSet.welcomeToApiResponse {
            precondition(welcomeResponse.toAddress != nil)
            setFinished(address: welcomeResponse.toAddress!)
            return
        }

        if let acceptTermsResponse = fullSet.acceptTermsResponse {
            precondition(acceptTermsResponse.toAddress != nil)

            if fullSet.acceptTermsRequest == nil {
                setAcceptTermsRequired(address: acceptTermsResponse.toAddress!)
            } else {
                setAcceptingTerms(address: acceptTermsResponse.toAddress!)
            }
            return
        }

        if let signUpRequest = fullSet.signUpRequest {
            precondition(signUpRequest.fromAddresses.first != nil)
            setSigningUp(address: signUpRequest.fromAddresses.first!)
        }
    }

    private func setFinished(address: String) {
        accountAddress = address
        print("found finished CrowdNode sign up, account: \(address)")
        signUpState = SignUpState.finished
        // TODO: refreshBalance()
        // TODO: tax category
    }

    private func setAcceptingTerms(address: String) {
        accountAddress = address
        print("found accept terms CrowdNode response, account: \(address)")
        signUpState = SignUpState.acceptingTerms
    }
    
    private func setAcceptTermsRequired(address: String) {
        accountAddress = address
        print("found accept terms CrowdNode response, account: \(address)")
        signUpState = SignUpState.acceptTermsRequired
    }

    private func setSigningUp(address: String) {
        accountAddress = address
        print("found signUp CrowdNode request, account: \(address)")
        signUpState = SignUpState.signingUp
    }
    
    private func reset() {
        print("CrowdNode reset triggered")
        signUpState = .notStarted
        accountAddress = ""
        apiError = nil
    }
}

extension CrowdNode {
    func signUp(accountAddress: String) async {
        self.accountAddress = accountAddress

        do {
            if signUpState < SignUpState.acceptTermsRequired {
                signUpState = SignUpState.fundingWallet
                let topUpTx = try await topUpAccount(accountAddress, CrowdNodeConstants.requiredForSignup)
                print("CrowdNode TopUp tx hash: \(topUpTx.txHashHexString)")
                
                signUpState = SignUpState.signingUp
                let (signUpTx, acceptTermsResponse) = try await makeSignUpRequest(accountAddress, [topUpTx])
                
                signUpState = SignUpState.acceptingTerms
                let _ = try await acceptTerms(accountAddress, [signUpTx, acceptTermsResponse])
            } else {
                signUpState = SignUpState.acceptingTerms
                let topUpTx = try await topUpAccount(accountAddress, CrowdNodeConstants.requiredForAcceptTerms)
                let _ = try await acceptTerms(accountAddress, [topUpTx])
            }

            signUpState = SignUpState.finished
        }
        catch {
            print("CrowdNode error: \(error)")
            signUpState = SignUpState.error
            apiError = error
        }
    }

    private func topUpAccount(_ accountAddress: String, _ amount: UInt64) async throws -> DSTransaction {
        let topUpTx = try await sendCoinsService.sendCoins(
            address: accountAddress,
            amount: amount
        )
        return await txObserver.first(filters: SpendableTransaction(txHashData: topUpTx.txHashData))
    }

    private func makeSignUpRequest(_ accountAddress: String, _ inputs: [DSTransaction]) async throws -> (req: DSTransaction, resp: DSTransaction) {
        let requestValue = CrowdNodeConstants.apiOffset + ApiCode.signUp.rawValue
        let signUpTx = try await sendCoinsService.sendCoins(
            address: CrowdNodeConstants.crowdNodeAddress,
            amount: requestValue,
            inputSelector: SingleInputAddressSelector(candidates: inputs, address: accountAddress)
        )
        print("CrowdNode SignUp tx hash: \(signUpTx.txHashHexString)")

        let successResponse = CrowdNodeResponse(
            responseCode: ApiCode.pleaseAcceptTerms,
            accountAddress: accountAddress
        )
        let errorResponse = CrowdNodeErrorResponse(
            errorValue: requestValue,
            accountAddress: accountAddress
        )

        let responseTx = await txObserver.first(filters: errorResponse, successResponse)
        print("CrowdNode AcceptTerms response tx hash: \(responseTx.txHashHexString)")

        if errorResponse.matches(tx: responseTx) {
            throw CrowdNodeError.signUp
        }

        return (req: signUpTx, resp: responseTx)
    }

    private func acceptTerms(_ accountAddress: String, _ inputs: [DSTransaction]) async throws -> (req: DSTransaction, resp: DSTransaction) {
        let requestValue = CrowdNodeConstants.apiOffset + ApiCode.acceptTerms.rawValue
        let termsAcceptedTx = try await sendCoinsService.sendCoins(
            address: CrowdNodeConstants.crowdNodeAddress,
            amount: requestValue,
            inputSelector: SingleInputAddressSelector(candidates: inputs, address: accountAddress)
        )
        print("CrowdNode Terms Accepted tx hash: \(termsAcceptedTx.txHashHexString)")

        let successResponse = CrowdNodeResponse(
            responseCode: ApiCode.welcomeToApi,
            accountAddress: accountAddress
        )
        let errorResponse = CrowdNodeErrorResponse(
            errorValue: requestValue,
            accountAddress: accountAddress
        )

        let responseTx = await txObserver.first(filters: errorResponse, successResponse)
        print("CrowdNode Welcome response tx hash: \(responseTx.txHashHexString)")

        if errorResponse.matches(tx: responseTx) {
            throw CrowdNodeError.signUp
        }

        return (req: termsAcceptedTx, resp: responseTx)
    }
}
