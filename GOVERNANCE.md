# Project governance

Blackout Kit Mobile is currently a single-maintainer project. The repository
owner (@kiacoder) is responsible for review, merge decisions, security disclosure,
release approval and maintaining the project's engineering standards. Ownership
does not mean that a change has received independent review.

## Contribution and merge policy

- Work on a topic branch or fork. Open a pull request targeting main.
- Explain intent, scope, tests, limitations, risk and rollback in the PR.
- Never commit credentials, private configuration profiles or identifying logs.
- Resolve review conversations and update the PR against current main.
- The required GitHub Actions check is currently the always-run Tests job
  (context `test`, GitHub Actions app 15368). It includes Flutter and Android JVM
  tests. Path-filtered checks are not required unconditionally: they may not run.
- A maintainer reviews every applicable check and security finding before merge,
  including platform builds, scanner reports and Rust/native checks. Required
  status checks are a minimum, not release authorization.
- Squash or rebase merges only; no direct pushes, force pushes or main deletion.
- Do not bypass protection just to clear a red check. Fix the underlying failure.
- No mandatory independent approval count until a second trusted maintainer is
  available. CODEOWNERS identifies responsibility, not mandatory self-approval.

## Signing and releases

- Official version tags match `v*`; only repository administrators may create
  them, and tags cannot be moved or deleted under the active integrity rule.
- Create official tags only from reviewed commits reachable from main.
- Tagged builds must use the existing Android release signing identity, verified
  against the published certificate fingerprint in RELEASE_SECURITY.md.
- The production-release environment allows only version tags and requires
  explicit approval from the repository owner before the draft publication job.
  The owner may approve their own deployment while the project has one maintainer.
- The android-release-signing environment has the same tag/approval policy;
  its signing secrets have NOT been migrated. Existing repository secrets must
  be securely re-entered from the original backup into that environment, and
  the signing workflow separated from unprivileged build jobs before removal of
  repository-level copies. Never attempt to retrieve or expose GitHub secrets.
- Do not create or publish a production release until actual security reports,
  compatibility, device acceptance and release checks have been reviewed.
- Immutable release assets and enforced verified Git commits are separate from
  protected tags. Enable immutability after the draft-first workflow lands on
  main. Enforce verified commits after maintainers have tested a signing setup.
  Do not rewrite the existing PR history to retrofit signatures.

## Security incidents and recovery

Report privately using [GitHub security advisories](https://github.com/kiacoder/blackout-kit-mobile/security/advisories/new)
and follow [SECURITY.md](SECURITY.md). Do not publish exploit details or private
user information in public issues. On suspected signing-key or credential
compromise:

1. Pause release workflows and publication; preserve relevant logs and hashes.
2. Revoke affected tokens and remove compromised automation access. Rotate
   credentials from a trusted workstation; do not overwrite a release key
   casually because Android update compatibility depends on its identity.
3. Investigate affected commits, tags, build provenance and distributed artifacts.
4. Communicate verified scope and safe remediation through official channels.
5. Recover through a reviewed PR and a new versioned release; never silently
   replace an existing release asset. Restore controls and document the incident.

## Expanding maintainership

Grant least-privilege access only after sustained trusted contributions. Once
an independent maintainer is available, require at least one approval for PRs,
CODEOWNERS review of sensitive areas, and independent release approval. Document
emergency access and require strong account authentication. Review governance
settings periodically. No bot may independently approve or merge its own changes.

## Current project state

See [Project Ascension](docs/PROJECT_ASCENSION.md) and
[release security policy](docs/RELEASE_SECURITY.md).
