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

public class CrowdNode {
    enum SignUpState: Comparable {
        case notStarted
        // Create New Account
        case fundingWallet
        case signingUp
        case acceptingTerms
        case finished
        case error
        // Link Existing Account
        case linkedOnline
    }

    private let sendCoinsService = SendCoinsService()
    private let txObserver = TransactionObserver()

    @Published private(set) var signUpState = SignUpState.notStarted
    private(set) var accountAddress: String = ""
    private(set) var apiError: Error?

    public static let shared: CrowdNode = .init()

    init() {
        restoreState()
    }
}

extension CrowdNode {
    private func restoreState() {
        if signUpState != SignUpState.notStarted {
            // Already started/restored
            return
        }

        print("restoring CrowdNode status")
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
            setAcceptingTerms(address: acceptTermsResponse.toAddress!)
            return
        }

        if let signUpRequest = fullSet.signUpRequest {
            precondition(signUpRequest.fromAddresses.first != nil)
            setSigningUp(address: signUpRequest.fromAddresses.first!)
        }
    }

    private func setFinished(address: String) {
        accountAddress = address
        print("found finished sign up, account: \(address)")
        signUpState = SignUpState.finished
        // TODO: refreshBalance()
        // TODO: tax category
    }

    private func setAcceptingTerms(address: String) {
        accountAddress = address
        print("found accept terms response, account: \(address)")
        signUpState = SignUpState.acceptingTerms
    }

    private func setSigningUp(address: String) {
        accountAddress = address
        print("found signUp request, account: \(address)")
        signUpState = SignUpState.signingUp
    }
}

extension CrowdNode {
    func signUp(accountAddress: String) async {
        self.accountAddress = accountAddress

        do {
            if signUpState < SignUpState.signingUp {
                signUpState = SignUpState.fundingWallet
                let topUpTx = try await topUpAccount(accountAddress)
                print("CrowdNode TopUp tx hash: \(topUpTx.txHashHexString)")

                signUpState = SignUpState.signingUp
                let (signUpTx, acceptTermsResponse) = try await makeSignUpRequest(accountAddress, [topUpTx])
                print("CrowdNode SignUp tx hash: \(signUpTx.txHashHexString)")
                print("CrowdNode AcceptTerms response tx hash: \(acceptTermsResponse.txHashHexString)")

                signUpState = SignUpState.acceptingTerms
                let (termsAcceptedTx, welcomeResponse) = try await acceptTerms(accountAddress, [signUpTx, acceptTermsResponse])
                print("CrowdNode Terms Accepted tx hash: \(termsAcceptedTx.txHashHexString)")
                print("CrowdNode Welcome response tx hash: \(welcomeResponse.txHashHexString)")

                signUpState = SignUpState.finished
            }
        }
        catch {
            signUpState = SignUpState.error
            apiError = error
        }
    }

    private func topUpAccount(_ accountAddress: String) async throws -> DSTransaction {
        let topUpTx = try await sendCoinsService.sendCoins(
            address: accountAddress,
            amount: CrowdNodeConstants.requiredForSignup
        )
        return await txObserver.first(filters: SpendableTransaction(txHashData: topUpTx.txHashData))
    }

    private func makeSignUpRequest(_ accountAddress: String, _ inputs: [DSTransaction]) async throws -> (req: DSTransaction, resp: DSTransaction) {
        let signUpTx = try await sendCoinsService.sendCoins(
            address: CrowdNodeConstants.crowdNodeAddress,
            amount: CrowdNodeConstants.apiOffset + ApiCode.signUp.rawValue,
            inputSelector: SingleInputAddressSelector(candidates: inputs, address: accountAddress)
        )

        let successResponse = CrowdNodeResponse(
            responseCode: ApiCode.pleaseAcceptTerms,
            accountAddress: accountAddress
        )
        let errorResponse = CrowdNodeErrorResponse(
            errorValue: CrowdNodeConstants.apiOffset + ApiCode.welcomeToApi.rawValue,
            accountAddress: accountAddress
        )

        let responseTx = await txObserver.first(filters: errorResponse, successResponse)

        if errorResponse.matches(tx: responseTx) {
            throw CrowdNodeError.signUp
        }

        return (req: signUpTx, resp: responseTx)
    }

    private func acceptTerms(_ accountAddress: String, _ inputs: [DSTransaction]) async throws -> (req: DSTransaction, resp: DSTransaction) {
        let termsAcceptedTx = try await sendCoinsService.sendCoins(
            address: CrowdNodeConstants.crowdNodeAddress,
            amount: CrowdNodeConstants.apiOffset + ApiCode.acceptTerms.rawValue,
            inputSelector: SingleInputAddressSelector(candidates: inputs, address: accountAddress)
        )

        let successResponse = CrowdNodeResponse(
            responseCode: ApiCode.welcomeToApi,
            accountAddress: accountAddress
        )
        let errorResponse = CrowdNodeErrorResponse(
            errorValue: successResponse.coins,
            accountAddress: accountAddress
        )

        let responseTx = await txObserver.first(filters: errorResponse, successResponse)

        if errorResponse.matches(tx: responseTx) {
            throw CrowdNodeError.signUp
        }

        return (req: termsAcceptedTx, resp: responseTx)
    }
}
