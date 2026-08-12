# Release automation setup

Tests need no Apple credentials:

```sh
bundle install
bundle exec fastlane test
```

TestFlight delivery is intentionally dormant until all of the following are
complete:

1. Enroll in the Apple Developer Program and create the app
   `com.reypryma.watake` in App Store Connect.
2. Create a private signing repository and initialize it locally with
   `bundle exec fastlane match appstore`.
3. Create an App Store Connect **team API key**.
4. Add these GitHub Actions secrets:
   `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`,
   `APP_STORE_CONNECT_KEY_CONTENT` (base64-encoded `.p8`),
   `MATCH_GIT_URL`, `MATCH_PASSWORD`, and, for HTTPS match repositories,
   `MATCH_GIT_BASIC_AUTHORIZATION`.
5. Create a GitHub environment named `testflight`.
6. Set the repository variable `ENABLE_APPLE_RELEASES=true`.

Ordinary merges to `main` never upload a build. Release Please maintains its
version PR; merging that PR creates a GitHub release, calls `release.yml`,
attaches the `.ipa`, and uploads the tagged build to TestFlight.

App Store delivery is intentionally on hold during initial TestFlight
development. No GitHub Actions workflow invokes the Fastlane `release` lane.
When App Store delivery is enabled later, create an `app-store` environment
with a required reviewer and retain explicit App Review submission.

Never commit `.p8`, `.p12`, provisioning profiles, passwords, or base64 key
content.
