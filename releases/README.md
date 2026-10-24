# Local build — debug-signed

`blackout-kit-v1.12.4-arm64-v8a-debug-signed.apk`

Built locally on 2026-10-24 from commit `6bc0e1c` (tag `v1.12.4`), arm64-v8a,
43.2 MB.

    versionName   1.12.4
    versionCode   2047
    package       com.blackoutkit.vpn
    minSdk        24
    sha256        52515b2f0715ce07dc578a4f8739eb40ca3bd04453ad1cb3d6dad9050d31a7b3

## This will NOT install over the app from the release page

It is signed with the **Android debug key** (`CN=Android Debug`), because the
release keystore only exists as CI secrets. Android refuses an update whose
signature differs from the installed app, so installing this over a
release-signed build fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`.

To use it, uninstall the current app first — **which erases your saved
configs**. Export them from the Library screen beforehand if you need them.

For a build that installs in place, use the release page instead:
https://github.com/kiacoder/blackout-kit-mobile/releases/tag/v1.12.4

Those APKs are signed with the release key and update normally.

## Why this is committed to the repository

It was asked for explicitly as a sideloadable artifact. Note that a 43 MB
binary lives in git history permanently — it is not something to repeat for
every build. Prefer the release assets, or a GitHub Actions artifact from a
`workflow_dispatch` run, for anything routine.
