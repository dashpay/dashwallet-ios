<!--- Provide a general summary of your changes in the Title above -->
<!--- Pull request titles must use the [conventional commits](https://www.conventionalcommits.org/en/v1.0.0/#summary) format -->

## Issue being fixed or feature implemented
<!--- Why is this change required? What problem does it solve? -->
<!--- If it fixes an open issue, please link to the issue here. -->


## What was done?
<!--- Describe your changes in detail -->


## How Has This Been Tested?
<!--- Please describe in detail how you tested your changes. -->
<!--- Include details of your testing environment, and the tests you ran to -->
<!--- see how your change affects other areas of the code, etc. -->


## Breaking Changes
<!--- Please describe any breaking changes your code introduces and verify that -->
<!--- the title includes "!" following the conventional commit type (e.g. "feat!: ..."-->


## Checklist:
<!--- Go over all the following points, and put an `x` in all the boxes that apply. -->
- [ ] I have performed a self-review of my own code
- [ ] I have commented my code, particularly in hard-to-understand areas
- [ ] I have added or updated relevant unit/integration/functional/e2e tests
- [ ] I have made corresponding changes to the documentation
- [ ] ADR ([ADR-0001](https://github.com/dashpay/dashwallet-ios/blob/develop/docs/adr/0001-record-architecture-decisions-as-adrs.md)), keep the answer that applies: `ADR-NNNN added` · `no significant decision` · `not needed: <N1–N4>`
- [ ] Nothing in this PR (files, commit messages, branch name, description, comments, attachments, linked issues) holds customer data, unfixed vulnerability detail, secrets, or step-by-step attack detail against keys, PIN or encryption; such content is left out and handled privately with the maintainers ([ADR-0001, rule 2](https://github.com/dashpay/dashwallet-ios/blob/develop/docs/adr/0001-record-architecture-decisions-as-adrs.md))

**For repository code-owners and collaborators only**
- [ ] I have assigned this pull request to a milestone
- [ ] If workflow-lint warned that a release-only step or `.xcode-version` changed, or a `.platform-ref` bump changed platform's Rust version, I ran the affected workflow by hand from this branch on the final commit (`release-dashpay-testflight.yml` with `wallet_ref` = that commit and `release_channel: internal-only`; `appstore-schema-release.yml` with `dry_run: true`) and linked the run here; a later push needs a new run
