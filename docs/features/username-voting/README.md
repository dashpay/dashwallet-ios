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

Stage 5b:

- **Request dates and links.** Each request shows its request date and "Link included" when it has
  a link; Request details shows the voting period from the earliest request date to the voting end.
  The dates come from SwiftDashSDK.
- **"Only requests with links".** The filter keeps only linked requests; while links are looked up
  the list shows loading, and when a link cannot be told it says it cannot filter by links and
  offers "Reset filters".
- **Quick voting.** "Quick voting" in the list's "…" menu approves the request submitted first under every
  shown username, from every ticked masternode, after one confirmation that names how many are
  voted for and how many are skipped. Names whose order or voting end cannot be told, closed names,
  names any masternode of this wallet blocked, and names with no votes left are skipped; an existing
  block or approve is never replaced. The votes go one after another under one PIN prompt
  ([ADR-0037](../../adr/0037-cast-quick-voting-sequentially-under-one-authentication.md)); a run
  with failures lists the usernames not voted for, with "Try again" for those only.

Stage 4:

- **Vote from the pills.** A tap on the block or approve pill sends the vote; the pill shows it is
  sending, and once it lands a toast confirms it and the pill is filled. A tap on a filled pill, or
  "Cancel approval" in Request details, cancels the vote with an abstain. While a vote sends, no
  other vote can start.
- **One gate order for every vote.** Voting has ended → voting not set up → "No votes left" → "One
  vote left" → for a block, the confirmation that a blocked name cannot be requested again. Only the
  first thing that stops a vote is shown
  ([ADR-0035](../../adr/0035-run-every-vote-through-a-pure-vote-attempt-state-machine.md)).
- **"Add your voting keys" with tick-boxes.** The first vote on this install opens it: this
  wallet's masternodes and imported keys, a "N votes will be cast" caption, a warning that voting
  together links masternodes, and a Block or Approve button that casts the vote without a second
  tap. Until it is confirmed once, no recorded vote counts as mine. "Voting keys" in the list's menu
  opens it to change the ticks later. The ticks stay as chosen: a masternode list that is still
  loading or incomplete never drops a ticked masternode
  ([ADR-0038](../../adr/0038-let-only-the-voting-store-write-the-remembered-node-choice.md)).
  "Enter voting key" follows the design and names its two refusals.
- **Outcomes.** A failed vote shows an error toast; when some masternodes' votes land and others
  fail, a sheet lists each one, and "Try again" resends from the failed ones only. A vote the
  masternodes already hold is not sent again, and a toast says so.
- **The list's bar and messages.** The DashUIKit navigation bar with a round back button and a
  "Voting keys" menu; refresh failed, node list incomplete and vote history unavailable show as one
  message above the rows. The old cast sheet, contest screen and node selection sheet are removed.

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
- No vote is sent before the owner has confirmed once which masternodes vote, and no block is sent
  without its confirmation.
- Only one vote sends at a time, and a vote the ticked masternodes already hold is not sent again.
- Quick voting never replaces an existing block or approve and never guesses which request came first.

## Not in scope here

- Votes cast from another device stay invisible: the vote history is local, as on Android.

The screens follow the design canon in [`docs/design-system.md`](../../design-system.md).
