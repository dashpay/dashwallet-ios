# Username voting: decide and vote from the list

**Owner:** romchornyi · Introduced in stages; this page grows with each stage PR.

## Why

A masternode owner opens Username Voting to decide who should get a contested name, and the old
screen gave them little to decide with: contenders by name and vote count only, the link, the
identity and the voting period behind a separate contest screen, bulk voting behind an unlabelled
menu, and an open contest that could disappear from the list mid-session. The Android wallet already
has the redesigned flow, and the designer has drawn it for iOS. Masternode owners vote from both
wallets, so iOS follows Android's rules where the design is silent, minus Android's known bugs.

## What changed

Stages 1–3 (this set of PRs):

- **The list follows the design.** A large title with an explanation, "All" with the number of open
  usernames, a username search, and the contests grouped under "Voting ends today / in N days",
  soonest day first; contests with no known voting end come last. Each row shows a block pill and an
  approve pill with their counts, and the pill that carries my vote is filled.
- **Filters.** A sheet sorts by date or by votes and keeps only names I approved, names I have not
  voted on, names with block votes, or names with several requests. A bar at the bottom names the
  sort. "Vote on several" is removed; Quick voting replaces it in a later stage.
- **Several requests open in place.** A name with more than one request shows «N requests» and an
  expand pill; it opens in place and lists each request with its own approve pill.
- **Request details opens straight from a row**, with the username, the link, the identity and the
  voting end. The separate contest screen is gone.
- **The list keeps what it knows.** A contest stays until its voting end even when a later read of
  it comes back empty or fails, newer data always wins over an older read, and a list that cannot
  load says so and offers Try again instead of showing an empty list.
- **One owner for voting state.** A shared store holds contests, masternodes, my vote history and
  the vote limit; each screen has a small view model over it
  ([ADR-0014](../../adr/0014-split-voting-state-into-a-shared-store-and-per-screen-view-models.md)).
  The shared components come from DashUIKit and the request dates from SwiftDashSDK, both changed
  through their own PRs ([ADR-0013](../../adr/0013-treat-dashuikit-and-swiftdashsdk-as-library-surfaces.md)).

## What it guarantees

- No masternode of this wallet votes more than 5 times on one contest; the limit is checked again
  before each cast.
- A vote that landed is never shown as not cast because an older list read arrived later.
- A contest is not removed from the list before its voting end.

## Not in scope here

Later stage PRs of the same feature:

- Voting straight from the pills, the "One vote left", "No votes left" and lock-is-final dialogs,
  the vote-result sheet, and "Add your voting keys" with tick-boxes (stage 4).
- Request dates, "Link included", the voting period start, "Only requests with links" and Quick
  voting (stage 5b, after the platform SDK change for request dates).
- Votes cast from another device stay invisible: the vote history is local, as on Android.

The screens follow the design canon in [`docs/design-system.md`](../../design-system.md).
