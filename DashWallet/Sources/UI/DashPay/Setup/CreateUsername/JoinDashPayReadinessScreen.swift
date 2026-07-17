//
//  JoinDashPayReadinessScreen.swift
//  DashWallet
//
//  "Get ready to join DashPay" interstitial. Shown between the Join
//  DashPay entry points and the Create Username form whenever the
//  shielded (privacy-preserving) funding path isn't ready yet, so the
//  user starts the privacy clock at first intent instead of hitting a
//  "come back in a few hours" wall after picking a name.
//
//  Live checklist of the three `ShieldedIdentityFundingReadiness`
//  gates: fund the shielded balance (button opens the existing
//  Shielded-balance transfer screen pre-filled with the shortfall),
//  let it rest (`maturityWindow`, countdown target shown), and the
//  consensus pool minimum (usually already met; surfaced only for
//  completeness/fresh networks). Continue unlocks at `.ready`; an
//  explicit "use transparent balance" escape keeps the old funding
//  paths one tap away for users who opt out of the wait.
//

import SwiftUI
import DashUIKit

struct JoinDashPayReadinessScreen: View {
    @ObservedObject private var readiness = ShieldedIdentityFundingReadiness.shared

    /// Open the Shielded-balance transfer screen pre-filled with the
    /// suggested deposit (in DASH).
    let onAddFunds: (Decimal) -> Void
    /// Push the Create Username form. Used by both Continue (shielded
    /// ready — the form's picker auto-pins to Shielded) and the
    /// transparent escape (the picker pins to the viable transparent
    /// source).
    let onProceed: () -> Void

    /// Suggested deposit headroom (0.001 DASH in credits) added to the
    /// shortfall prefill: the Core→Shielded route carves the Platform
    /// pool fee from the locked value, so depositing the bare shortfall
    /// would net slightly under the denomination. Only a suggestion —
    /// the gates re-evaluate on the notes that actually land.
    private static let fundingFeeHeadroomCredits: UInt64 = 100_000_000

    private var snapshot: ShieldedIdentityFundingReadiness.Snapshot? {
        readiness.standardSnapshot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(NSLocalizedString("Get ready to join DashPay", comment: "Usernames"))
                .font(.title1)
                .foregroundColor(.dash.primaryText)
                .padding(.top, 12)

            Text(NSLocalizedString("Your username is visible to everyone. Funding it from your Shielded balance — after letting the funds rest for a few hours — means no one can link your username to your other Dash.", comment: "Usernames"))
                .font(.system(size: 14))
                .foregroundColor(.dash.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 18) {
                fundingRow
                maturityRow
                poolRow
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dash.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.top, 24)

            Spacer()

            DashButton(
                text: NSLocalizedString("Continue", comment: ""),
                isEnabled: snapshot?.state == .ready
            ) {
                onProceed()
            }

            if snapshot?.state != .ready && transparentSourceViable {
                Button(action: onProceed) {
                    Text(NSLocalizedString("Use transparent balance instead", comment: "Usernames"))
                        .font(.footnote)
                        .foregroundColor(.dash.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 12)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dash.primaryBackground.ignoresSafeArea())
        .onAppear {
            readiness.refresh()
            // Pull fresh notes + the pool count so the checklist isn't
            // stale from the last periodic pass.
            readiness.requestFreshSignals()
        }
    }

    // MARK: - Checklist rows

    private var requiredCredits: UInt64 {
        snapshot?.requiredCredits ?? ShieldedIdentityFundingReadiness.standardDenominationCredits
    }

    private var isFunded: Bool {
        (snapshot?.unspentCredits ?? 0) >= requiredCredits
    }

    private var isMatured: Bool {
        (snapshot?.matureCredits ?? 0) >= requiredCredits
    }

    private var fundingRow: some View {
        checklistRow(
            met: isFunded,
            pendingIcon: "circle",
            title: String.localizedStringWithFormat(
                NSLocalizedString("Add at least %@ Dash to your Shielded balance", comment: "Usernames"),
                formatCredits(requiredCredits)),
            subtitle: isFunded
                ? String.localizedStringWithFormat(
                    NSLocalizedString("%@ Dash available", comment: "Usernames"),
                    formatCredits(snapshot?.unspentCredits ?? 0))
                : String.localizedStringWithFormat(
                    NSLocalizedString("You have %@ Dash so far", comment: "Usernames"),
                    formatCredits(snapshot?.unspentCredits ?? 0)),
            trailing: isFunded ? nil : (
                NSLocalizedString("Add", comment: ""),
                {
                    let shortfall: UInt64
                    if case .needsFunding(let credits) = snapshot?.state {
                        shortfall = credits
                    } else {
                        shortfall = requiredCredits
                    }
                    onAddFunds(Self.dashAmount(credits: shortfall + Self.fundingFeeHeadroomCredits))
                }
            ))
    }

    private var maturityRow: some View {
        let subtitle: String
        if isMatured {
            subtitle = NSLocalizedString("Done — your balance has rested long enough", comment: "Usernames")
        } else if case .maturing(let readyAt) = snapshot?.state {
            let time = DateFormatter.localizedString(from: readyAt, dateStyle: .none, timeStyle: .short)
            subtitle = String.localizedStringWithFormat(
                NSLocalizedString("Ready around %@", comment: "Usernames"), time)
        } else {
            subtitle = NSLocalizedString("Starts after you add funds", comment: "Usernames")
        }
        return checklistRow(
            met: isMatured,
            pendingIcon: isFunded ? "clock" : "circle",
            title: NSLocalizedString("Let it rest for a few hours", comment: "Usernames"),
            subtitle: subtitle,
            trailing: nil)
    }

    private var poolRow: some View {
        let met: Bool
        let pendingIcon: String
        let subtitle: String
        if let count = snapshot?.poolNoteCount {
            met = count >= ShieldedIdentityFundingReadiness.minimumPoolNotes
            pendingIcon = "circle"
            subtitle = met
                ? NSLocalizedString("Minimum met", comment: "Usernames")
                : String.localizedStringWithFormat(
                    NSLocalizedString("%ld of %ld deposits", comment: "Usernames"),
                    Int(count), Int(ShieldedIdentityFundingReadiness.minimumPoolNotes))
        } else {
            // Count not reported yet. Never claim the check passed —
            // but an unknown count doesn't block Continue either
            // (readiness fails open here); Drive enforces the real
            // rule at registration, so say exactly that.
            met = false
            pendingIcon = "questionmark.circle"
            subtitle = NSLocalizedString("Verified during registration", comment: "Usernames")
        }
        return checklistRow(
            met: met,
            pendingIcon: pendingIcon,
            title: NSLocalizedString("Shared privacy pool at minimum size", comment: "Usernames"),
            subtitle: subtitle,
            trailing: nil)
    }

    private func checklistRow(
        met: Bool,
        pendingIcon: String,
        title: String,
        subtitle: String,
        trailing: (String, () -> Void)?
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: met ? "checkmark.circle.fill" : pendingIcon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(met ? .green : .dash.gray300)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.dash.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let (label, action) = trailing {
                Button(action: action) {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.dash.whiteText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.dash.blue)
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Helpers

    /// The transparent escape is only offered when it can actually
    /// complete a registration — otherwise it would land the user on a
    /// form whose Continue is disabled by the cost rule.
    private var transparentSourceViable: Bool {
        let core = SwiftDashSDKWalletState.shared.balance?.total ?? 0
        let platform = SwiftDashSDKWalletState.shared.platformPaymentCreditsAsDuffs
        return core >= DWDP_MIN_BALANCE_TO_CREATE_USERNAME
            || platform >= DWDP_MIN_BALANCE_TO_CREATE_USERNAME
    }

    /// Credits → whole-DASH decimal (1e11 credits per DASH).
    private static func dashAmount(credits: UInt64) -> Decimal {
        Decimal(credits) / Decimal(100_000_000_000)
    }

    /// Credits → formatted DASH string (credits ÷ 1000 = duffs).
    private func formatCredits(_ credits: UInt64) -> String {
        (credits / 1_000).dashAmount.formattedDashAmountWithoutCurrencySymbol
    }
}
