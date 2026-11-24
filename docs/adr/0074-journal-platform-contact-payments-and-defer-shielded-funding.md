# 0074 — Journal Platform contact payments and defer Shielded funding

- **Status:** Proposed
- **Date:** 2026-11-24
- **Deciders:** pasta (funding scope); maintainers (review pending).

## Context

Platform-funded DashPay payments reserve a contact address before submitting a withdrawal. The SDK returns no Core payout transaction ID, so sending, contact history and wallet removal need a shared record of the attempt. Shielded activity is a display projection rather than an authoritative recovery record; hosts cannot use it alone to decide whether another payment is safe.

## Decision drivers

- Preserve payment uncertainty across restart and wallet changes.
- Keep address allocation distinct from submission and receipt.
- Offer only funding sources whose current app flow is supported.
- Give history and wallet removal the same persisted contract.

## Considered options

1. Journal Platform contact withdrawals and defer Shielded contact funding until SDK recovery is available.
2. Enable both withdrawal sources using the Shielded activity projection.
3. Defer all withdrawal-funded contact payments.

## Decision outcome

**Chosen:** journal Platform contact payments, retain Transparent contact payments, and refuse new Shielded contact payments in both source selection and execution.

The journal is scoped to concrete chain, wallet and owner identity. Its states describe local evidence:

| State | Meaning |
|---|---|
| `reserving` | Written before address allocation; no withdrawal dispatched yet. |
| `unused` | The withdrawal was proven not submitted; the address may still be consumed. |
| `submitting` | The destination is recorded before invoking the withdrawal; an interrupted call may have succeeded. |
| `submitted` | The SDK accepted the withdrawal, without proving Core payout receipt. |
| `unconfirmed` | The submission outcome is unknown. |
| `corePayment` | A successful Transparent contact payment, used to end the unpaid-address streak. |

The SDK owns address allocation and submission. The recipient's Core chain history establishes receipt; the local journal never claims to establish it. Five potentially unpaid reservations stop further withdrawal address allocation. Proven non-submission keeps its allocation record; releasing a payment lock does not refund that budget.

Unresolved Platform attempts block ordinary contact payment across all sources. After the time and chain-progress backstop, the journal offers an explicit decision about another payment, with a duplicate-payment warning; it does not infer receipt or nonreceipt. Session locks and journal scopes bind that decision to the original sender. Unreadable state fails closed and history reports incompleteness.

Earlier builds' Shielded records remain readable; disabling new Shielded contact funding does not discard their history or clear their locks. Restoring that funding requires a durable SDK operation identity or authoritative reconciliation that distinguishes a never-submitted withdrawal from one that can still execute. Ordinary Shielded address withdrawals are unaffected.

Authorized wallet removal clears the journal only after SDK deletion succeeds, across all chain scopes of the removed wallet IDs. Full wipe clears the whole journal. Staged files remain readable until retired; failed retirement cleanup fails closed rather than exposing partial history. Session locks are cleared only after successful journal cleanup. A failed retired-directory cleanup currently affects other wallets as well; narrowing that failure scope is a separate improvement.

## Consequences

- Platform-funded payments no longer require Transparent spending funds.
- Shielded-only users cannot pay a contact directly until the SDK recovery prerequisite is implemented.
- The journal preserves uncertainty and allocation accounting, but does not reconcile asynchronous Core payouts.
- Existing journal schema and Shielded records remain compatible. A later recovery implementation must define migration and retention before changing their meaning.

## Links

- [Decision-log rules](0001-record-architecture-decisions-as-adrs.md)
- [Withdrawal journal](../../DashWallet/Sources/Infrastructure/SwiftDashSDK/Contacts/DashPayWithdrawalStore.swift)
- [Contact execution boundary](../../DashWallet/Sources/UI/Payments/InternalTransfer/Shielded/ShieldedTransferCoordinator.swift)
