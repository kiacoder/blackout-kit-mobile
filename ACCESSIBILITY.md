# Accessibility Statement

**Blackout Kit Mobile** · last updated 2026-11-02

## Our commitment

Blackout Kit exists so that people under internet censorship can reach the
open web — and that mission is meaningless if the tool itself excludes
people. We aim to follow WCAG 2.1 Level AA guidance where it applies to a
mobile application: sufficient contrast, text that scales with system font
settings, touch targets large enough for comfortable use, full right-to-left
layout support, and no feature that depends on a single sense.

This is a commitment, not a completed audit — see *Known limitations*.

## Supported environments

| | |
|---|---|
| Android | 7.0 (API 24) and later, phones and tablets; arm64-v8a and armeabi-v7a |
| iOS | 13.0 and later, iPhone (build available; distribution is unsigned — see IOS_SUPPORT.md) |
| Languages | English, Persian (فارسی, full RTL), Chinese (中文) — 427 keys each, with runtime language switching |
| Display | Dark and light themes; system font scaling respected by Flutter's text stack |

## What we do today

- **Localization**: the entire UI is translated in all three languages, with
  Persian layouts mirrored end-to-end (RTL) and language switchable at
  runtime without restarting the app.
- **RTL**: Persian is a first-class layout direction, not a string swap —
  paddings, chips, titles and truncation are RTL-aware.
- **Contrast**: both themes are designed to keep text legible; the dark
  theme is the default.
- **Simple primary flow**: one large Connect control, plain-language status
  messages, and errors surfaced verbatim instead of silent failures.
- **No flashing / motion-dependent UI**: status is communicated by text and
  static color, with accompanying labels.

## Known limitations

We state these plainly so nobody has to discover them the hard way:

- **Screen readers (TalkBack / VoiceOver)**: the UI is built with Flutter's
  standard widgets, but the app has **not yet had a full screen-reader
  audit**. Missing labels or focus-order oddities are possible, especially
  in the config library lists and the on-screen log/debug surfaces.
- **Color-only signaling**: some status indicators lean on color (green /
  red) in addition to text. Where text is present this is acceptable, but a
  color-only signal would be a bug — please report it.
- **Small text in technical surfaces**: log and diagnostic views can render
  dense monospaced text that is difficult at large font scales.
- **Accessibility of the *environment***: a censorship-circumvention tool
  inherently asks users to manage files, developer options (USB debugging
  for logs) and app-install prompts — steps that are themselves barriers.
  We try to minimize them; we cannot remove all of them from the OS side.
- **Third-party engines**: the bundled Xray / sing-box / tun2socks cores and
  Libbox are upstream projects; their own accessibility is outside our
  control.

## Reporting barriers

If any part of the app is hard or impossible for you to use, that is a bug
and we want it:

1. **Preferred**: open a [GitHub issue](https://github.com/kiacoder/blackout-kit-mobile/issues/new/choose)
   and include the word **accessibility** in the title — these are triaged
   alongside functional bugs.
2. If GitHub is itself a barrier for you (a real possibility for our
   users), email **security@blackout-kit.dev** with "Accessibility" in the
   subject and we will post the issue on your behalf without revealing your
   identity.

Please include: device and OS version, the assistive technology you use
(screen reader, font scale, input method), the screen you were on, and what
you expected versus what happened. Screenshots help; descriptions help just
as much.

## How we prioritize

Accessibility reports are treated as functional bugs. Reported barriers are
labeled `accessibility`, and screen-reader labeling for any new screen is
part of the definition of done for UI contributions (see
[CONTRIBUTING.md](CONTRIBUTING.md)).
