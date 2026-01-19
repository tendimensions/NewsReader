# NewsReader

A custom news reader application built with Flutter for iOS and Android platforms.

## Project Overview

NewsReader is a cross-platform mobile application designed to provide users with a personalized news reading experience. The app will be developed using Flutter, built on CodeMagic CI/CD, and distributed via Firebase App Distribution.

## Status

🚧 **In Development** - Initial setup phase

## Technology Stack

- **Framework**: Flutter
- **Platforms**: iOS, Android
- **CI/CD**: CodeMagic
- **Distribution**: Firebase App Distribution

## Configuration Pending

The following aspects are still being defined:

- **News Sources/APIs**: To be determined
- **Features**: Full feature specification document to be created
- **Architecture Pattern**: To be decided (see common Flutter patterns below)
- **State Management**: To be selected

## Common Flutter Architecture Patterns

For reference, the most commonly used architecture patterns in Flutter applications are:

1. **Provider + MVVM** - Most popular for small to medium apps
2. **BLoC (Business Logic Component)** - Popular for larger, enterprise applications
3. **Riverpod** - Modern evolution of Provider, gaining popularity
4. **GetX** - All-in-one solution (state management, routing, dependency injection)
5. **Clean Architecture** - Often combined with the above patterns for larger apps

## Getting Started

### Prerequisites

- Flutter SDK installed
- iOS development: Xcode and CocoaPods
- Android development: Android Studio and Android SDK

### Installation

```bash
# Get dependencies
flutter pub get

# Run the app
flutter run
```

## Project Structure

```
news_reader/
├── android/          # Android-specific code
├── ios/              # iOS-specific code
├── lib/              # Main Flutter application code
├── test/             # Unit and widget tests
└── web/              # Web platform support
```

## Development

This project uses the standard Flutter development workflow:

```bash
# Run in debug mode
flutter run

# Run tests
flutter test

# Build for release
flutter build apk       # Android
flutter build ios       # iOS
```

## Contributing

More details to be added as the project structure is finalized.

## License

To be determined
