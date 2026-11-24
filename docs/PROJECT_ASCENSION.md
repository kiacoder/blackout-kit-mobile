# Project Ascension ? professional repository program

## Roadmap

| Phase | Focus | State |
| --- | --- | --- |
| 0 | Security remediation and PR #20 acceptance | In progress |
| 1 | Repository governance | Core settings active; migration/review pending |
| 2 | Supply-chain security | Initial gates implemented; CI and review pending |
| 3 | Code quality engineering | Planned |
| 4 | Advanced automated testing | Planned |
| 5 | Android device laboratory | Planned |
| 6 | Performance engineering | Planned |
| 7 | Reliability and privacy-preserving diagnostics | Planned |
| 8 | Release engineering | Planned |
| 9 | Documentation and branding | Planned |
| 10 | Community and organic growth | Planned |
| 11 | Project management automation | Planned |
| 12 | Independent trust and auditing | Planned |
| 13 | Shared Black Series engineering standards | Planned |

Do not treat planned capabilities as implemented. Each phase has independent
acceptance evidence. Track unresolved risks rather than accumulating badges.

## Phase 1 ? 2026-11-24

Baseline: public repository, sole admin @kiacoder, basic main protection,
existing contribution/security files and private reporting, discussions enabled.
Default Actions token is read-only; workflow approval of PRs is disabled.
No existing rulesets; no verified local commit-signing configuration.

Live rulesets created and read back from the GitHub API:

| Name | ID | Enforcement |
| --- | --- | --- |
| Ascension - protect main | 27996090 | Active |
| Ascension - release tag creation | 27996091 | Active |
| Ascension - release tag integrity | 27996092 | Active |

Main requires PRs, resolved review threads, linear history, up-to-date required
Tests check from GitHub Actions (app 15368), no deletion or force push, no
ruleset bypass actors. Zero required approvals is deliberate for a one-person
project; squash or rebase only. Separate rulesets restrict v* tag creation to
admins and prevent tag modification/deletion without disabling the integrity
rule. Emergency changes to rulesets require explicit admin authorization.

Environments production-release and android-release-signing have tag-only v*
policies and owner review. Self-review allowed deliberately while there is a
single maintainer. The new draft publishing job references production-release.
Signing environment is staged, not yet used for credential isolation.
CODEOWNERS, governance policy and PR review checklist added on the integration
branch. They are not effective on main until merged.

Pending: secure migration of Android signing secrets and isolated signing job;
verified commit signing setup; independent reviewer when available; immutable
releases after draft-first workflow merges; comprehensive aggregate CI merge
gate after path-filtered workflows are redesigned. Existing repository-level
signing secrets are unchanged. No test tag or public release created.

Phase 0 status at audit: latest build APK workflow succeeded; separate iOS
compile run failed because GitHub could not allocate a macOS hosted runner,
not because of a compile error. Failed job rerun requested. CodeQL and actual
MobSF/VirusTotal report review remain separate; do not merge PR #20 merely
because governance settings have been enabled.

References:
https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets
https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments
https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners


## Phase 2 - supply-chain security, 2026-11-24

- All direct external workflow references pinned to full Git commit SHAs.
  All existing checkout steps disable credential persistence.
- New Supply chain security workflow: dependency review on PRs (high and
  critical introduced advisories fail), cargo-deny advisory/license/source
  policy, zizmor workflow analysis, OSV new-vulnerability PR scans and full
  scans, Gradle wrapper validation, tracked binary and action-pin integrity.
- OpenSSF Scorecard workflow: weekly/manual and integration-branch baseline
  push, JSON evidence artifact, publishing disabled until the baseline is
  reviewed. No score or badge claimed.
- Cargo Dependabot updates grouped weekly. No automatic merging.
- Gradle 7.6.6 all distribution pinned to official SHA-256:
  6ed4d467349e2d3f555a578829c4aeadd67d73e2ec5d213c2a62f8f2829d9fa9.
  Source: https://services.gradle.org/distributions/gradle-7.6.6-all.zip.sha256
  Existing wrapper JAR is a historical version; independent wrapper validation
  must confirm it is a recognized official wrapper.
- Machine-readable baseline for 12 tracked binary files, including the AAR
  and both nested JNI hashes, five native shared libraries, Gradle wrapper,
  and five historical APKs. CI verifies paths and hashes before any build in
  the existing Tests and APK workflows. A matching checksum proves unchanged
  bytes, not verified upstream source provenance or malware-free status.
- Six synthetic regression tests cover valid manifest, altered/unknown binary,
  duplicate entry, mutable action ref and allowed local action.
- Rust license policy permits observed permissive SPDX terms; this does not
  clear licenses of opaque native libraries. No advisory exceptions added.

Local validation: 12 artifact hashes match; six new tests pass; actionlint
passes all ten workflows. No new scanner result or complete CI verdict
claimed yet. The new supply-chain jobs are not yet added to the required
main ruleset; the existing mandatory Tests job now includes integrity.
Review results and then require stable checks. Independent tools may have
transitive container tags/installers outside our direct action pin check.
Gitleaks, Trivy, provenance reconstruction for historic prebuilt engines,
release secret migration, and public Scorecard publication remain follow-up.

Phase 0 evidence update: run 45421149333 succeeded, including the MobSF
step. VirusTotal logged unknown-file for all three APK hashes; this is not
an antivirus verdict. Full MobSF report review is still pending, and no
production merge or release is approved here.

References:
https://github.com/actions/dependency-review-action
https://github.com/EmbarkStudios/cargo-deny-action
https://github.com/google/osv-scanner-action
https://github.com/zizmorcore/zizmor-action
https://github.com/ossf/scorecard-action
https://github.com/gradle/actions
