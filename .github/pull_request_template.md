<!--
  Stuck on the description? Run `/pr-description` in Claude Code — it reads the
  branch diff and fills this template. You review + edit before submitting.
-->

## Summary

<!-- 1–3 bullets on what changed and why. Not what files. -->

-
-

## Screenshots (UI changes only)

| Before | After |
|---|---|
|  |  |

## Test plan

<!-- Checklist a reviewer can actually run. -->

- [ ] `bundle exec fastlane test` green
- [ ] Manually verified on iPhone simulator
- [ ] Manually verified on iPad simulator (if layout changed)
- [ ] Snapshot tests updated (if watermark render changed)

## Parity

<!-- If this is a user-visible feature, mirror it on Android. Update docs/PARITY.md in the parent repo. -->

- [ ] No Android counterpart needed
- [ ] Android issue linked: `watake_android#___`
- [ ] `docs/PARITY.md` updated in parent repo

## Release notes

<!-- One line. Goes into the auto-generated changelog. -->

## Checklist

- [ ] Conventional commit title (`feat:`, `fix:`, etc.)
- [ ] SwiftLint + SwiftFormat green locally
- [ ] No secrets, keys, `.p8`, `.p12`, or `.env` staged
- [ ] Files under 1000 lines (SwiftLint warns at 800, blocks at 1200)
