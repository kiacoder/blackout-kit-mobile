<!--
  Thanks for contributing! Keep PRs focused: one logical change per PR.
  The full process lives in CONTRIBUTING.md.
-->

## What does this PR change?

<!-- One or two sentences: what and why. Link issues with Fixes #123. -->

## Type of change

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing behavior to change)
- [ ] Documentation / CI only

## Checklist

- [ ] `flutter analyze` passes
- [ ] `flutter test` passes (and new behavior has a regression test where it makes sense)
- [ ] For native/Rust changes: `cargo test` passes in `native/blackout-core`
- [ ] No secrets, keystore files, or personal data in the diff
- [ ] `CHANGELOG.md` has an entry under `[Unreleased]` (user-visible changes only)
- [ ] Version-sensitive docs (PHASES.md status notes, IOS_SUPPORT.md) updated if behavior claims changed

- [ ] Applicable CI and security findings reviewed; no unresolved release blockers
- [ ] Native/device claims backed by evidence, or experimental gates retained
- [ ] Security-sensitive changes identify trust boundaries, privacy impact and rollback
- [ ] No production release or signing-key changes without explicit maintainer approval

## Risk, verification and rollback

<!-- Describe test evidence, known limitations and how to revert safely. -->

## Notes for the reviewer

<!-- Anything worth calling out: risky areas, trade-offs, follow-up work. -->
