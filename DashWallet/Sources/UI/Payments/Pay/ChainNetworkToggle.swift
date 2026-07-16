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
        case .core: return NSLocalizedString("Core", comment: "Dash Core chain")
        case .platform: return NSLocalizedString("Platform", comment: "Dash Platform chain")
        case .shielded: return NSLocalizedString("Shielded", comment: "")
        }
    }
}

struct ChainNetworkToggle: View {
    @Binding var selection: ChainNetwork
    /// Which networks this surface offers. Defaults to the sendable pair;
    /// the Receive landing passes all cases to add Shielded.
    var options: [ChainNetwork] = [.core, .platform]

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options) { network in
                Text(network.title).tag(network)
            }
        }
        .pickerStyle(.segmented)
    }
}
