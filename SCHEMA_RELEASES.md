# SwiftData schemas and App Store releases

The TestFlight pipeline captures schema evidence. Publication in App Store
Connect triggers a separate freeze PR in `dashpay/platform`. TestFlight builds
do not become historical schema versions merely because they were uploaded.
The accepted V1 remains unchanged. Historical V2 is reconstructed from source
`52e8d4ec68f0c772313fa1bbef223fb1eabbf1cc`, matching all 35 model hashes and
the checksum of an observed App Store 9.0.2 store. This proves the model shape,
not the exact source commit of Apple's binary. Active models are now V3. An older app may have written a
different, unversioned model graph while still labelling its store `1.0.0`.
The SDK provides a bounded compatibility bridge for these legacy stores, as
described below. Other intermediate development databases remain unsupported.
Never reset an App Store user's database as a substitute for migration.

## Legacy database compatibility

The app opens its per-network SQLite store through
`DashModelContainer.createAsync(url:)`, sharing the SDK's migration behavior.
Store opening and migration run on a dedicated queue; concurrent requests for
the same network share one in-flight open. Contexts stay on their owning actor.
Known
schemas use the normal migration plan. For an unrecognized legacy `1.0.0`
store, the SDK attempts automatic migration on an isolated, consistent copy to
the specific V3 schema. It verifies preservation of existing stored data and
relationships and checks that the normal plan can reopen the migrated store
before accepting it. A backup remains through the migration/recovery launch and
is reclaimed after a later successful ordinary open; failed opens never trigger
cleanup. The recovery journal retains a fingerprint of the validated final data
so missing scratch files need not block recovery. Failure must never
erase the user's database. Newer schema versions and corrupt stores do not
qualify for this bridge.

Remove and Delete All also discard completed migration snapshots through the
SDK before deleting SDK keys or live wallet rows, including cached containers,
empty stores and inactive network stores. A snapshot contains the entire old
store, so removing one wallet discards that completed snapshot while preserving
other wallets' current rows. A pending migration journal or cleanup failure
stops SDK deletion and is reported to the caller. Whole-app wipe may already
have removed legacy DashSync mnemonic entries in its existing first phase;
snapshot cleanup is not an atomic transaction with that legacy cleanup.

This bridge runs once per database, independently of the App Store observer
and its `bootstrap` operation. It does not modify frozen V1 or establish which
source commit was published. Regression fixtures include synthetic data made
from Platform `fd8d8d13e5d7cea17b00df5974934ab1910e8039`, paired with iOS
`8094751eb2be8d52b57da3589fdd2ae2dcd0ecc6` in
[Actions run 32706880873](https://github.com/dashpay/dashwallet-ios/actions/runs/32706880873).
That run failed before upload; its commits identify the tested sources, not
proven App Store provenance. See the SDK fixture manifest for reproduction.

Retain the bridge for users who skip the V3 app and upgrade directly to a later app.
When introducing V4, keep the bridge destination on the frozen V3 models, then
use the ordinary V3-to-current migration plan. Exact accepted V1 uses a separate
V1-to-V3 route: passing it through historical V2 would drop 13 populated fields.
Historical V2 uses V2-to-V3. Do not point the legacy bridge
at whichever models happen to be current.

## Initial setup

1. Before merging, create a fine-grained PAT restricted to `dashpay/dashwallet-ios` and
   `dashpay/platform`, with Contents, Actions and Pull requests read/write.
   Approve it in the organization if required. Store it as
   `SCHEMA_RELEASE_TOKEN` in both repositories (or an organization secret limited
   to them). The existing App Store Connect key stays in the iOS `testflight`
   environment; Platform does not need it.
2. Merge the Platform schema release support into `v4.2-dev`, then merge this
   repository's support into `develop`. These must remain the default branches
   for the workflows to appear and the schedule to run. Complete initialization
   before starting the next `internal` or `external` build.
3. In **Freeze published App Store schema**, choose `bootstrap` and keep
   `dry_run` enabled. Confirm the version printed is the already accepted first
   App Store release and matches the verified historical binding in Platform's
   registry. Bootstrap refuses to assign V1 or guess a schema for an unverified
   release. Repeat with `dry_run` disabled **before shipping the next version**.
   This creates the isolated `schema-release-data` branch and its baseline.
   Until this step completes, production-capable builds intentionally stop at
   preflight with setup instructions. `internal-only` builds remain available.
4. Run `sync` in dry-run mode, then enable repository variable
   `SCHEMA_RELEASE_ENABLED=true`. The observer runs at 05:17 and 17:17 UTC.
   Keep the automation able to use its environment without interactive approval
   if unattended scheduled checks are required.
   This variable controls the schedule only; it never bypasses candidate checks.

Do not merge `schema-release-data` into application code. Permit the automation
to fast-forward that branch; prohibit force pushes/deletion. The branch contains
only synthetic fixtures and release provenance, never secrets or user data.
Protect Platform tags matching `swift-schema-source/*` against updates and
deletion. Each lightweight tag points to the exact full SHA in its name. The
candidate workflow creates it before recording evidence and uploading, so a
later development-branch rewrite cannot discard the released model sources.
PAT updates write metadata and create draft freeze branches/PRs; nobody needs to
grant the bot permission to merge protected development branches.

## Building and publishing

Use `internal` or `external` for a build that may reach the App Store.
`internal-only` cannot be promoted and skips the release-schema gates/capture.

Before archive and again before upload, the pipeline reads Apple's published
versions and checks that each post-baseline release has a merged freeze **in
the selected Platform commit**. Choosing an older SHA without that freeze fails
even if the latest development branch has it.
The first check runs before release-version resolution and the native build.
The selected Platform checkout must contain the registry and capture tooling
and all four required test classes even when there are no new publications to
reconcile. Missing release scripts are rejected before the build begins.

After archive, the pipeline runs the SDK's offline migration, legacy-bridge,
release-compatibility and capture tests in Release on an arm64 iOS simulator. It reuses the simulator
slice built alongside the device FFI. The populated store is created from the
same Platform sources; it is not extracted from the device binary. The capture
contains the schema version, entity hashes, checksum, and SQLite indexes, plus
toolchain metadata. Indexes are checked separately because entity hashes do not
cover them.
Before the native capture starts, `freeze_schema_models.py --check-inventory`
checks that supported stored declarations reference only inventoried or standard
types, including nested value-type fields and enum payloads. Missing types or
unsupported declaration syntax stop capture before evidence is recorded.

The branch records `builds/<bundle>/<app-version>/<build>/manifest.json` and
`stores/<sha256>.store` before upload, then `apple-builds/<id>.json` when processing
finishes. Existing build evidence cannot be overwritten. If a failed upload left
evidence under a reserved version/build tuple, the next run automatically skips
that number; do not delete or rewrite the evidence to reuse it. Concurrent writers retry a
non-fast-forward conflict without force pushing.

## Freeze and review

The observer confirms publication through App Store Connect, obtains that
version's selected build, and records `releases/<version-id>.json`. It dispatches
Platform with that release ID and a pinned metadata commit. Platform validates
the evidence and creates a draft PR from the recorded Platform SHA. A repeated
observation reuses its branch/PR; identical schema releases share a snapshot.

Review the freeze PR, resolve any migration failures, and merge it manually.
The next observation (or release preflight) sees the merged registry. The iOS
data branch records a merged status on the next observation. A GitHub Actions
summary includes a link to the deterministic freeze PR search.

Publication preserves a historical snapshot without changing live model types
or automatically adding a schema version. At the next structural change,
register the old version using its snapshot, add the new live version, and test
the migration. If development advanced before publication, the freeze PR exposes
that mismatch; it must not roll back current code or invent a migration.

## Manual checks and recovery

- Choose `sync` in **Freeze published App Store schema** to check immediately.
  Optionally provide an App Store version ID. Manual operation still requires
  publication and never freezes an arbitrary commit. Uncheck `dry_run` to write
  evidence and dispatch the PR; its default is read-only.
  A specific version ID can also use its previously recorded publication proof
  if Apple no longer lists the release. The original build evidence and checksums
  are still required; retry never changes the recorded build or publication.
- A lost upload-processing callback is recoverable: publication resolves the
  exact bundle/version/build tuple against the evidence recorded before upload.
- Missing or contradictory provenance blocks dispatch. Recover the original
  build evidence; do not substitute today's code or regenerate its historical
  store from the current branch.
- Failed dispatches are retried on the next run. Worker runs are serialized,
  branches are deterministic, and existing human edits are preserved. Resolve
  conflicts in the existing PR rather than deleting/replacing immutable data.
- Apple's `REPLACED_WITH_NEW_VERSION` state also counts as published history,
  so a release superseded between two observations is still frozen.
- The current `appVersionState` takes precedence over legacy `appStoreState`.
  An unknown current state fails with an actionable error rather than silently
  skipping the release or trusting the deprecated field. Update the observer's
  state mapping after checking Apple's documentation, then retry. This strict
  history check applies to the observer and promotable candidate gates;
  `internal-only` version selection still uses known published versions and
  does not fail just because Apple adds an unknown state.
  A legacy-only `DEVELOPER_REMOVED_FROM_SALE` or `REMOVED_FROM_SALE` response
  for a version newer than the accepted baseline stops schema observation and
  candidate gates because it does not establish publication history. Older
  history is already covered by the baseline. Bootstrap selects the newest
  known publication and still rejects ambiguous newer versions. This history
  check does not block `internal-only` TestFlight version
  resolution, which still checks known published versions. Inspect
  that version in App Store Connect and recover its current version state;
  do not mark it published or substitute a build to make the check pass.
- Malformed publication records, unknown publication states, missing Apple
  build relationships and bad release evidence are reported per release
  without preventing independent valid releases or retained-proof manual retries
  from reaching their freeze PRs. The observation run still fails and
  the next candidate remains blocked until every required release is reconciled.
- Concurrent metadata writes wait for stale branch reads to catch up before
  revalidating the evidence. If the branch still has not advanced, the operation
  stops rather than blindly repeating a rejected or ambiguous write.
- The gate checks all observed production releases, including previously
  observed releases later removed from distribution. Polling cannot guarantee
  detection of a release published and removed entirely between checks; run a
  manual check at publication if such a rapid rollback is needed.
- A same-version schema or index conflict requires manual investigation and
  migration work. It is not repaired by changing the recorded checksum.
- Rotate `SCHEMA_RELEASE_TOKEN` in both repos before expiry. Authentication/API
  failures fail the workflow and block candidate upload; internal-only builds
  remain available. Scheduled runs may be delayed or disabled by GitHub after
  repository inactivity; inspect the Actions page or run a manual check.
- GitHub GET requests retry transient HTTP and connection errors up to four
  attempts. Writes are not blindly retried after an ambiguous failure: inspect
  the remote data branch or dispatched workflow before retrying. Existing
  immutable evidence is preserved; ordinary concurrent ref conflicts still
  use the atomic reconciliation loop.

## First publication and failure recovery

For the first tracked App Store release, the release operator verifies the whole
chain: the published Apple build matches the saved manifest, the Platform source
tag and captured fixture are present, the worker opens the expected draft PR,
and its checks pass before manual merge. A successful observer run only means
that it dispatched the worker; inspect the separate Platform run and PR too.

If scheduled observation has not run or failed, start **Freeze published App
Store schema** manually in `sync` mode. Use `dry_run` to inspect the result, then
disable it to record publication and dispatch. A worker failure is retried by
the next observation or by the Platform workflow with the same release ID and
metadata commit. Fix the reported cause first. Retries preserve the original
build evidence and reuse the existing PR; they never substitute current HEAD.

The existing App Store app is unaffected by a failed freeze job. Subsequent
`internal`/`external` candidates remain blocked until the required snapshot is
merged and included in the selected Platform commit. Manual dispatch retains
the publication/evidence checks; it is not an override for missing provenance.

Both workflows report failures in Actions. The release operator should enable
[GitHub Actions failure notifications](https://docs.github.com/en/actions/concepts/workflows-and-actions/notifications-for-workflow-runs)
and verify the recipient for scheduled runs (normally the last editor of the
cron schedule). There is no separate team alert or app telemetry for this
process. A disabled schedule produces no failed run, so checking the freeze PR
is part of the release checklist even when notifications are enabled.

## Local tooling tests

```sh
ruby -I.github/scripts -e 'Dir[".github/scripts/*_test.rb"].sort.each { |file| require File.expand_path(file) }'
python3 -m unittest discover -s .github/scripts -p 'test_*.py' -v
```

Use Ruby 3.3 or newer. These tests mock Apple/GitHub and do not publish, upload,
commit or push anything. Platform's Python generator tests and simulator schema
tests verify the other half of the contract.

## Correcting the existing 9.0.2 baseline after historical V2 reconstruction

Deploy the Platform migration fix first, then this repository's gate changes.
Do not run bootstrap again or move `max_app_version` forward. Review an ordinary
fast-forward commit on `schema-release-data` that retains the existing app ID,
release ID, version 9.0.2 and `accepted_at`, changes `schema_version` from
`1.0.0` to `2.0.0`, and adds `model_checksum` from the reviewed historical V2
registry and `schema_provenance: reconstructed-model-match`. Record the old
baseline SHA-256 and the reason in a separate correction record. Re-read the
branch before applying the correction; if the baseline bytes changed, stop and
review the new state rather than overwriting it. This is a reviewed deployment
operation, not part of normal observer runs.

Candidate preflight now verifies the historical fixture digest and frozen V2
sources in the **selected** Platform checkout, even with no post-baseline
publications. It also rejects the obsolete V1 association for this release.
After the correction, run observer `sync` with `dry_run: true`, then create a
new candidate carrying schema V3. Leave the existing TestFlight 9.1.1 (30)
manifest, capture and `swift-schema-source/*` tag unchanged. They describe the
actual earlier build and are not evidence for the reconstructed App Store V2.
