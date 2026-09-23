# Mac App Store metadata

`GitStrideAppStore` and the GitHub Release target both use bundle ID `tech.hyperseek.gitstride`. The `fastlane/metadata` folder contains English and Simplified Chinese product-page text and URLs. Screenshots are intentionally managed separately.

Apple requires the macOS App record to exist before the official App Store Connect API or `deliver` can update it. Create a macOS record named **GitStride**, with primary language **English (U.S.)**, bundle ID and SKU `tech.hyperseek.gitstride`. Register the bundle ID first if needed. Do not submit a version for review until its screenshots, build, review login, and other required disclosures are ready.

Install the pinned fastlane version with `bundle install`. Copy `fastlane/.env.example` to `fastlane/.env`, then set the existing App Store Connect individual API key ID and `.p8` path. Keep `.env` and the key outside Git. Verify and upload text/URLs from the repository root:

```sh
bundle exec fastlane verify_metadata
bundle exec fastlane mac upload_metadata
```

The upload lane skips screenshots, build upload, and review submission. App Review contact name, email, and phone files are ignored by Git; use the same contact details as the other Hyperseek apps. App Review notes explain the OAuth Device Flow, but a stable reviewer GitHub account with a Project is still needed before review submission.

The privacy answers include account identifiers and the optional hosted automation service's retained connection data. `fastlane/app_privacy_details.json` records **User ID** and **Other Data**, linked to the user and used for app functionality. The official API does not expose App Privacy answers; fastlane's `mac upload_privacy_details` uses Apple ID authentication with owner/admin access. Set `ASC_APPLE_ID` and complete Apple's sign-in challenge when ready. The privacy policy URL itself is included in each localization's metadata.

Use `bundle exec ruby fastlane/exclude_china_mainland.rb` to mark **China mainland unavailable** through the App Store Connect API and verify it. The script changes no other territory. The binary, App Review login, age rating, encryption declaration, pricing, and remaining compliance questions are separate release inputs.
