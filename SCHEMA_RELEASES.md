# SwiftData schemas and App Store releases

The TestFlight pipeline captures schema evidence. Publication in App Store
Connect triggers a separate freeze PR in `dashpay/platform`. TestFlight builds
do not become historical schema versions merely because they were uploaded.
V1 is the accepted baseline; intermediate development databases are unsupported
and may require a deliberate reset. Never reset an App Store user's database as
a substitute for migration.

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
   App Store release. Repeat with `dry_run` disabled **before shipping the next
   version**. This creates the isolated `schema-release-data` branch and its
   immutable baseline; it does not inspect or reconstruct V1's original code.
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
even when there are no new publications to reconcile.

After archive, the pipeline runs the SDK's offline migration, release-compatibility
and capture tests in Release on an arm64 iOS simulator. It reuses the simulator
slice built alongside the device FFI. The populated store is created from the
same Platform sources; it is not extracted from the device binary. The capture
contains the schema version, entity hashes, checksum, and SQLite indexes, plus
toolchain metadata. Indexes are checked separately because entity hashes do not
cover them.

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
  A legacy-only `DEVELOPER_REMOVED_FROM_SALE` or `REMOVED_FROM_SALE` response
  stops processing because it does not establish publication history. Inspect
  that version in App Store Connect and recover its current version state;
  do not mark it published or substitute a build to make the check pass.
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

## Local tooling tests

```sh
ruby -I.github/scripts -e 'Dir[".github/scripts/*_test.rb"].sort.each { |file| require File.expand_path(file) }'
python3 -m unittest discover -s .github/scripts -p 'test_*.py' -v
```

Use Ruby 3.3 or newer. These tests mock Apple/GitHub and do not publish, upload,
commit or push anything. Platform's Python generator tests and simulator schema
tests verify the other half of the contract.
