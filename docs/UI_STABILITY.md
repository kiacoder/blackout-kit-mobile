# UI stability follow-up

Reported symptom: intermittent crashes while opening screens or tapping controls
in the first side-by-side native Android test build. No device crash trace was
available during this investigation (ADB had no connected phone).

Fixed concrete Flutter defects:
- Engine Hub filters now use stable category IDs, not localized labels. Reactive
  subscriptions remain valid even with an empty category. Engine cards constrain
  badges and protocol chips for narrow screens.
- Import defers initial clipboard/share handling until the first frame, prioritizes
  explicit shared payloads, guards late scanner/clipboard callbacks and only closes
  the route associated with an asynchronous successful save.
- Editor suppresses duplicate saves and checks route ownership before navigation.
- Logs checks mounted after confirmation; the update checker checks mounted before
  initial state changes. Preferred-protocol dialog subscribes even when no engine
  is available.

Host verification: 554/554 Flutter tests passed, including three new interaction
regressions (Persian and Chinese Engine Hub filters at 360 logical pixels, and a
known empty engine capability report). Static analysis exits 0 with 200 existing
info-level findings. Native transport code is unchanged. These fixes do not
establish that the reported Android process crash is resolved; obtain a device
crash stack and reproduce on the next test APK. Do not claim physical acceptance
or production readiness.
