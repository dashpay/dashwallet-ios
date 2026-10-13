//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
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

import Foundation

/// A wallet on one chain: the wallet id and the chain's persistence scope
/// (`Network.persistenceScope`: "mainnet", "testnet", or "devnet-<name>").
///
/// A seed's wallet id differs between mainnet, testnet and devnet
/// (key-wallet folds the network into it), but it is the same on every
/// named devnet, while each devnet has its own transaction store. So on a
/// devnet the wallet id alone does not say whose rows, sends or coins
/// something is; the chain does.
///
/// What a send is signed under (read in the same main-actor hop as its
/// build), what a followed send is kept under, and what the Home pending
/// caption is read for.
struct WalletChainScope: Equatable, Hashable {
    let walletId: Data
    /// `Network.persistenceScope` of the chain.
    let chain: String
}
