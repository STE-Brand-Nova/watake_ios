# Release automation setup

Tests need no Apple credentials:

```sh
bundle install
bundle exec fastlane test
```

TestFlight and App Store jobs are intentionally dormant until all of the
following are complete:

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
5. Create GitHub environments named `testflight` and `app-store`. Add a
   required reviewer to `app-store`.
6. Set the repository variable `ENABLE_APPLE_RELEASES=true`.

`beta.yml` uploads merged `main` builds to TestFlight. Release Please creates a
version PR and GitHub release. The release job attaches the `.ipa` and uploads
the build to App Store Connect. It does **not** submit for App Review unless
`SUBMIT_FOR_REVIEW=true` is explicitly supplied.

Never commit `.p8`, `.p12`, provisioning profiles, passwords, or base64 key
content.

