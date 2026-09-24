# Releasing GitStride

This guide covers ZIP distribution through [gitstride.hyperseek.tech](https://gitstride.hyperseek.tech) and [zwyyy456/GitStride Releases](https://github.com/zwyyy456/GitStride/releases). It does not deploy the website or Automation Worker.

The client and release artifacts use GitStride. The repository, website, and Sparkle feed still use their existing URLs. When those resources move, update `GitStride/Info.plist` (`SUFeedURL`), the download prefix and website link in `update_appcast.sh`, and the channel link in `appcast.xml` together. Feed entries must match the exact published ZIP bytes.

## Distribution targets and desktop OAuth

`GitStride` is the Developer ID / GitHub Release target. `GitStrideAppStore` shares the app sources, enables App Sandbox with outgoing network access, and excludes the CLI runner and Sparkle. Both targets use bundle ID `tech.hyperseek.gitstride`. Use the App Store target's shared scheme to archive for App Store Connect; the ZIP and appcast script remain specific to the Release target. The GitHub release script sets its version and build only for that archive; set the App Store target's version and build separately when shipping it.

Both targets use the public `GITSTRIDE_OAUTH_CLIENT_ID` build setting. Register a desktop OAuth App separately from the Worker OAuth App and enable Device Flow. Never embed a Client Secret or reuse Worker access/refresh tokens. Signed Keychain access and container behavior must be checked with the actual distribution signing setup; unsigned builds do not validate these permissions.

## Mac App Store support purchase

The App Store target offers an optional repeatable support purchase in the About window. It does not unlock features. The `GitStrideAppStore` scheme is already the App Store archive scheme and does not link Sparkle. The GitHub Release build cannot use this StoreKit purchase; its Developer ID distribution needs a separate payment method if support payments are offered there.

In App Store Connect, accept the Paid Apps Agreement and create a **Consumable** in-app purchase for bundle ID `tech.hyperseek.gitstride` with product ID `tech.hyperseek.gitstride.support`. Use a support-oriented display name and description that clearly say no features are unlocked. Set the China mainland storefront price to ¥6 and select the desired US price point near $1 separately; App Store Connect controls actual storefront prices, and the app displays the local price returned by StoreKit. Add localization and the required review screenshot, then submit this first consumable with the app version for review.

Archive and upload the `GitStrideAppStore` scheme with App Store distribution signing. Before submission, test the purchase in Apple's sandbox or TestFlight, including a second purchase of the same product, cancellation, pending approval, and recovery of an unfinished transaction. An unsigned compile check does not verify App Store provisioning or live billing.

## Version and update feed

Pass the public version to `build_release.sh`. It sets `MARKETING_VERSION` for that archive and sets `CURRENT_PROJECT_VERSION` to one more than the larger of the project's current build and the builds in local `appcast.xml`. It does not edit the Xcode project. A failed attempt before the appcast is updated can reuse the same build; each published update needs a higher build number and a new public version so its ZIP filename is unique. The GitHub Release tag is supplied separately; it need not match the displayed app version exactly.

`update_appcast.sh` reads the exported app's version and build number, packages the app as `GitStride-VERSION.zip`, and uses Sparkle to generate the update entry and sign the ZIP. It checks the generated URL, versions, archive length, and signature before uploading.

`appcast.xml` is Sparkle's update catalog. The application reads it from this repository's `main` branch and downloads the referenced packages from GitHub Releases. An empty feed advertises no updates. It should contain only entries for packages that are available to users.

If an existing GitHub Release asset is deliberately replaced, regenerate its appcast entry from the exact replacement ZIP using Sparkle's `generate_appcast` and the `gitstride` signing account. Verify the enclosure URL, byte length, versions, and signature with `sign_update --verify`. Publish the regenerated feed only after the replacement asset is downloadable. Repacking the app creates different ZIP bytes and requires a new signature. `update_appcast.sh` refuses to overwrite existing assets; use it for new releases.

## One-time signing setup

1. In Xcode → Settings → Accounts, select your Apple developer account and team. The checked-in GitStride team is `G38CM6VNCC`.
2. Under Manage Certificates, create or import a **Developer ID Application** certificate and its private key. An Apple Development or Mac App Store distribution certificate serves a different distribution method. The release export uses Developer ID and inherits the team from the archive.
3. Use the Sparkle tools resolved by Xcode from `Package.resolved`. Run `generate_keys` from their `bin` directory:

   ```bash
   ./bin/generate_keys --account gitstride
   ```

   This creates or reuses a signing key in your login Keychain and prints its **public** key. Put that public key in `GitStride/Info.plist` under `SUPublicEDKey`. Keep the private key in Keychain and back it up securely outside the repository. The ZIP release script checks the exported app's public key against this account.

4. Store your notarization credentials using `xcrun notarytool store-credentials gitstride-notary` and follow its interactive prompts. Apple documents the accepted account/API-key credentials in its [notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Sparkle's key signs update archives. Apple's Developer ID certificate signs the app. Both are used in this release process; neither private key belongs in Git.

## Build and publish a notarized ZIP

Run the relevant build and behavior checks from [the command index](../docs-index.md). Sign in to `gh` for `zwyyy456/GitStride`, install the Developer ID Application certificate and its private key, keep the Sparkle `gitstride` key in Keychain, and store the `gitstride-notary` credentials as described above. Create the GitHub Release for the intended source commit and tag before running the script. For example, after reviewing the version and release notes:

```bash
gh release create v1.0.1 --repo zwyyy456/GitStride --target SOURCE_COMMIT \
  --title "GitStride 1.0.1" --notes-file RELEASE_NOTES.md
```

Pass the public version and that exact tag to the script. Add `--notes /path/to/release-notes.html` when you have current HTML notes for Sparkle:

```bash
./build_release.sh 1.0.1 --tag v1.0.1
```

`build_release.sh` archives and exports the Release target with Developer ID signing, submits a temporary ZIP to Apple's notary service, staples and validates the ticket on the exported app, then calls `update_appcast.sh`. That script checks the signing identity and Sparkle key, creates and signs `build/release/GitStride-VERSION.zip`, uploads it to the existing GitHub Release, and updates local `appcast.xml`. The archive, dSYMs, exported app, and notarization result remain in a versioned directory under `build/release/`. Neither script replaces an existing release ZIP or Release asset. Delta generation is disabled. Do not change ZIP bytes after the Sparkle signature is generated.

For an app that was already notarized and stapled, `update_appcast.sh /path/to/GitStride.app --tag RELEASE_TAG` remains available. Apple's notarization ticket must be stapled to the `.app` before final ZIP packaging; a ZIP cannot be stapled directly. Do not modify the app after notarization.

## Publish

1. Verify the uploaded ZIP is downloadable and installs correctly, then commit and publish the generated `appcast.xml` to `main`.
2. Update the download link on `gitstride.hyperseek.tech` to the same Release asset. Website/DNS changes are separate from this script.
3. Verify an older-to-newer Sparkle update on a separate test Mac or test account, including every CPU architecture advertised for the release. Use screenshots supplied from the running app when visual review is needed.

The script uploads the ZIP, but it does not create a Release, push Git commits, deploy the website, or modify DNS. Keep the exported archive and dSYMs so crash reports from the distributed build can be symbolicated.

## References

- [Sparkle distribution and appcast generation](https://sparkle-project.org/documentation/)
- [Publishing Sparkle updates](https://sparkle-project.org/documentation/publishing/)
- [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
