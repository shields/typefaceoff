# Release Typeface/Off

The **Release** workflow checks for passing main pushes every 15 minutes and on
manual dispatch. It uses the full source history for gitcalver. A release has
the tag `v0.YYYYMMDD.N`, marketing version `0.YYYYMMDD.N`, and Mac build number
`YYYYMMDD.N`. GitHub and App Store Connect each release only the newest passing
main push, and Homebrew only the newest published disk image, so a push that a
newer passing push has superseded by the time of a run is never released. App
Review is manual.

## First release

1. Merge the companion cask qualification change into `shields/homebrew-tap`.
   The first signed release supplies `Casks/typefaceoff.rb` and its checksum.
   The tap’s required **Check tap** job must qualify the cask before auto-merge.
2. In the source repository’s GitHub settings, enable immutable releases
   **before publishing the first one**. Create the environments in the table
   below and restrict deployment branches to `main`. The tap App installation
   needs contents and pull request write access to `shields/homebrew-tap`.
3. Register the explicit App ID `com.typefaceoff` and its macOS app record in
   App Store Connect. Create the Mac App Store provisioning profile for that app
   and its Apple Distribution certificate. Obtain a Mac Installer Distribution
   certificate for the signed Store package. Export the signing identities with
   their private keys into the password-protected PKCS#12 files below.
4. Merge the release workflow into main when you’re ready to publish. The main
   push that introduces the workflow is the first release candidate. Once its
   checks pass, the next scheduled run picks it up unless a newer push has
   passed. You can also run **Release → Run workflow** on main.

| GitHub environment | Secrets                                                                                                                                                                                                                                | Variables                                                                           |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `developer-id`     | `SIGNING_P12` (base64 Developer ID Application identity), `P12_PASSWORD`, `ASC_PRIVATE_KEY` (notarization team API key, PEM text)                                                                                                      | `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`                                      |
| `app-store`        | `SIGNING_P12` (base64 PKCS#12 containing Apple Distribution and Mac Installer Distribution identities), `P12_PASSWORD`, `STORE_PROFILE` (base64 Mac App Store provisioning profile), `ASC_PRIVATE_KEY` (upload team API key, PEM text) | `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_APP_ID` (numeric app Apple ID) |
| `homebrew`         | `TAP_APP_PRIVATE_KEY`                                                                                                                                                                                                                  | `TAP_APP_CLIENT_ID`                                                                 |

Enter secret values through GitHub’s secret input or pipe them directly to
`gh secret set`. Use a team API key authorized for notarization in the first
environment and a key with build upload and read access in the second. The
hosted runner imports signing identities into a temporary keychain. Apple will
require current agreements and valid certificates and profiles.

## Disk image

On a Mac with the Developer ID Application identity, configure a `notarytool`
Keychain profile called `typefaceoff-notary` (override with `NOTARY_PROFILE`).
From a clean main release commit, run `make dmg`. `DEVELOPER_ID_IDENTITY` can
select a particular signing identity if the Keychain has several. The output is
under `.build/developer-id/assets/`.

The image contains the universal `TypefaceOff.app` and an Applications link. The
build checks the archive’s notices and SPDX inventory, signs the image, submits
it for notarization, staples the accepted ticket, checks Gatekeeper, mounts the
result, and compares the packaged bundle with the archive. GitHub publishes the
image, the corresponding SPDX file, `SHA256SUMS`, and `release.json` containing
the full commit and version. Homebrew pins the published DMG asset’s SHA-256.
Check a downloaded release with `shasum -a 256 -c SHA256SUMS` beside the DMG and
SPDX file.

For a packaging check without Apple credentials, run `make ci-dmg`. It writes an
unsigned development image to `.build/ci-distribution/assets/`. For the first
signed release, download the DMG through a browser on a clean Mac, disconnect
the network, mount the image, drag the app to Applications, eject the image, and
launch the installed app. Check About for the release version and compare two
installed fonts.

## App Store listing

Use the name **Typeface/Off**, category **Graphics & Design**, price **Free**,
and the same marketing version as the uploaded build. Use
`https://typefaceoff.com/support` for support and
`https://typefaceoff.com/privacy` for privacy. Both pages are reachable from the
app’s Help menu.

Suggested English description:

> Compare the fonts installed on your Mac. Read the same passage in two
> typefaces, overlay individual glyphs to see how their shapes and spacing
> differ, and explore the languages each font covers. Typeface/Off runs offline
> and keeps your specimen text on your Mac.

Run `make store-screenshots` to capture the Text, Glyph, and Languages views in
the Tart test VM as lossless, opaque PNGs in `.build/app-store/screenshots/`.
Supply the owner’s review contact information in App Store Connect, complete the
age rating questionnaire, and set the privacy response to **Data Not Collected**
for the current offline app. For review notes, explain that the reviewer can
select two installed fonts and switch among Text, Glyph, and Languages without
an account. Select a processed build for the matching version, submit it for App
Review, and release the approved version for free.

## Retries

The queue checks CI (including its tested-tree reuse), workflow provenance, and
workflow security for the main push SHA. GitHub commit statuses named
`release/dmg`, `release/store`, and `release/tap` record a published immutable
release, an Apple-processed valid build, and a merged cask update respectively.
Each interval picks, per channel, the newest passing push above the channel’s
newest status of any state, and the tap channel proposes the newest published
disk image. A push whose checks are still running or failing does not hold back
an older passing one, except that the tap channel proposes nothing while the
newest published disk image’s checks are not passing. Check the linked Actions
run for failures.

A retry repairs an incomplete GitHub draft and reuses a published release. The
Store job checks Apple’s build record before uploading, waits for processing,
and records a failed Store status if Apple reports the build as failed or
invalid. That failure stays visible while subsequent builds continue. The tap
job reads the immutable release, closes its open PRs for older versions, opens
or reuses its PR (replacing it with a new PR from tap main if it conflicts),
enables checked auto-merge, and confirms the version on tap main on a subsequent
run.

A failed channel retries the same commit on every interval, and dispatching
**Release** on main retries it too, until a newer push passes (for Homebrew,
until a newer disk image is published). Retry by dispatching, not by re-running
failed jobs of an older run, which replays that run’s commit even after a newer
one was released. Re-running a push’s checks makes the queue treat that push as
not passing until they pass again. Each job runs the scripts of the commit it
releases, so a fix for a failure in them lands in that newer push. To stop
retrying a commit that cannot be released, post a failure status for its
channel, for example
`gh api repos/shields/typefaceoff/statuses/<sha> -f state=failure -f context=release/dmg`.
The channel then waits for a push newer than that commit, as it does after a
Store rejection, and the tap channel never proposes a commit whose disk image
was not published. Fix a rejected binary in a newer commit if the existing
version can no longer be uploaded.
