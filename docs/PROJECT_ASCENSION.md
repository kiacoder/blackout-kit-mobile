# Project Ascension ? professional repository program

## Roadmap

| Phase | Focus | State |
| --- | --- | --- |
| 0 | Security remediation and PR #20 acceptance | In progress |
| 1 | Repository governance | Core settings active; migration/review pending |
| 2 | Supply-chain security | Planned |
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
