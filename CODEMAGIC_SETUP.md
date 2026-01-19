# CodeMagic Setup Guide for NewsReader

## Prerequisites

1. **CodeMagic Account**: Sign up at https://codemagic.io
2. **Firebase Project**: Create a project at https://console.firebase.google.com
3. **NewsAPI.org Key**: Get your API key from https://newsapi.org

## Environment Variables to Configure in CodeMagic

Go to your app settings in CodeMagic and add these environment variables (marked as secure):

### Required for All Builds

- `NEWS_API_KEY` - Your NewsAPI.org API key
- `FIREBASE_SERVICE_ACCOUNT` - Firebase service account JSON (for App Distribution)

### iOS Specific

- `FIREBASE_APP_ID_IOS` - Firebase iOS app ID (format: `1:123456789:ios:abcdef123456`)
- `APP_STORE_CONNECT_ISSUER_ID` - App Store Connect API issuer ID (for future App Store releases)
- `APP_STORE_CONNECT_KEY_IDENTIFIER` - App Store Connect API key ID
- `APP_STORE_CONNECT_PRIVATE_KEY` - App Store Connect API private key

### Android Specific

- `FIREBASE_APP_ID_ANDROID` - Firebase Android app ID (format: `1:123456789:android:abcdef123456`)

## Firebase Setup Steps

1. **Create Firebase Project**
   - Go to https://console.firebase.google.com
   - Click "Add project"
   - Name it "NewsReader"

2. **Add iOS App**
   - Click "Add app" → iOS
   - iOS bundle ID: `com.softupdate.newsReader`
   - Download `GoogleService-Info.plist`
   - Place in `ios/Runner/` directory

3. **Add Android App**
   - Click "Add app" → Android
   - Android package name: `com.softupdate.newsReader`
   - Download `google-services.json`
   - Place in `android/app/` directory

4. **Enable App Distribution**
   - In Firebase Console → Release & Monitor → App Distribution
   - Set up tester groups: "testers" and "internal"

5. **Generate Service Account**
   - Project Settings → Service Accounts
   - Click "Generate new private key"
   - Save JSON file
   - Copy entire content to `FIREBASE_SERVICE_ACCOUNT` variable in CodeMagic

## iOS Code Signing

1. **In CodeMagic**:
   - Go to Teams → Code signing identities
   - Upload your iOS distribution certificate and provisioning profile
   - Or use CodeMagic automatic code signing

2. **Update codemagic.yaml** if bundle ID differs:
   - Change `bundle_identifier: com.softupdate.newsReader` to your actual bundle ID

## Android Code Signing

1. **Generate Keystore** (if you don't have one):
   ```bash
   keytool -genkey -v -keystore newsreader-upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

2. **Upload to CodeMagic**:
   - Go to Teams → Code signing identities → Android
   - Upload your keystore file
   - Add keystore password, key alias, and key password

3. **Reference in codemagic.yaml**:
   - Update `keystore_reference` to match your uploaded keystore name

## Workflows

### ios-workflow
- Triggers on push to `main` or `develop`
- Runs tests
- Builds iOS IPA
- Deploys to Firebase App Distribution

### android-workflow
- Triggers on push to `main` or `develop`
- Runs tests
- Builds APK and AAB
- Deploys to Firebase App Distribution

### dev-workflow
- Triggers on any pull request
- Quick validation (analyze + test + debug build)
- No distribution

## Email Notifications

Update email recipients in `codemagic.yaml`:
```yaml
email:
  recipients:
    - your-email@example.com
```

## Next Steps

1. Push `codemagic.yaml` to your repository
2. Connect repository to CodeMagic
3. Configure environment variables
4. Upload code signing certificates
5. Trigger first build

## Useful Links

- CodeMagic Documentation: https://docs.codemagic.io/flutter-configuration/flutter-projects/
- Firebase App Distribution: https://firebase.google.com/docs/app-distribution
- Flutter CI/CD: https://docs.flutter.dev/deployment/cd
