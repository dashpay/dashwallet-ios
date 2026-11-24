//
//  ChainNetworkToggle.swift
//  DashWallet
//

import SwiftUI

enum ChainNetwork: String, CaseIterable, Identifiable {
    case core
    case platform
    /// The private shielded balance. Only offered where the wallet can
    /// actually produce a shielded payment address (the Receive landing);
    /// the Send screen can't pay to one, so its toggle never lists it.
    case shielded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .core: return String(localized: "Core", comment: "Dash Core chain")
        case .platform: return String(localized: "Platform", comment: "Dash Platform chain")
        case .shielded: return String(localized: "Shielded", comment: "")
        }
    }

    /// User-facing name of the BALANCE this chain holds. The home balance rows
    /// and the transfer screens call the Core balance "Transparent"; `title`
    /// stays the chain's own name for the Send/Receive segmented toggle. One
    /// source of truth so a row label and its insufficient-funds message can't
    /// name the same balance differently.
    var balanceName: String {
        switch self {
        case .core:
            // "Transparent" only makes sense opposite "Shielded", and only to
            // someone who has been shown that there are several balances.
            // Advanced mode is where that happens; without it the wallet
            // presents one balance and calls it what the app is called.
            //
            // Read here rather than passed in, deliberately: every caller wants
            // the same answer, and a parameter is a thing a future call site
            // can forget — which would put the word back on a screen that must
            // not carry it.
            return DWGlobalOptions.sharedInstance().advancedModeEnabled
                ? String(localized: "Transparent", comment: "Balance breakdown")
                : String(localized: "Dash Wallet", comment: "Balance breakdown, simple mode")
        case .platform: return String(localized: "Platform", comment: "Dash Platform chain")
        case .shielded: return String(localized: "Shielded", comment: "")
        }
    }
}

struct ChainNetworkToggle: View {
    @Binding var selection: ChainNetwork
    /// Which networks this surface offers. Defaults to the sendable pair;
    /// the Receive landing passes all cases to add Shielded.
    var options: [ChainNetwork] = [.core, .platform]

    var body: some View {
        Picker("" as String, selection: $selection) {
            ForEach(options) { network in
                Text(network.title).tag(network)
            }
        }
        .pickerStyle(.segmented)
    }
}
