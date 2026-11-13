# OpenTune

Privacy-first offline Android music player.

## Android compatibility
- Configured minimum Android version: **Android 7.0 (API 24)**.
- Android 7.0–12L: requests legacy `READ_EXTERNAL_STORAGE` at runtime.
- Android 13+: requests `READ_MEDIA_AUDIO`.
- MediaStore is used for local audio discovery; playback uses just_audio (Android ExoPlayer backend).
- audio_service supplies the media session and foreground notification controls.

## Features in this branch
- Kotlin MediaStore audio scan.
- Local content URI playback.
- Play/pause, previous/next, seek bar and background media service.
- Notification/lock-screen media actions through Android media session.
- Search, album and artist grouping, rescan and empty/error states.

## Architecture
- Flutter/Dart: UI and app state.
- Kotlin: Android MediaStore scanner and SDK bridge.
- just_audio: audio playback.
- audio_service: media session, foreground service and notification actions.
- Rust is not bundled: it would add binary/build overhead without improving basic playback.

## Build setup
This repository contains Android Gradle configuration, but the Gradle wrapper JAR and machine-local `android/local.properties` are generated locally by Flutter and are not checked in here. With Flutter installed, run:

```sh
flutter create --platforms=android .
flutter pub get
flutter analyze
flutter build apk --debug
```

If `flutter create` updates Android project files, retain the app's `minSdkVersion 24`, package namespace and audio-service manifest declarations.

## Device verification still required
No build or physical-device test has been run from this GitHub editing session. Verify Android 7.0, Android 8/9, Android 12L, Android 13+, local MP3/AAC/FLAC playback, notification/lock-screen buttons, headset controls, audio focus and background resume. Android 7.0 support is configured but is not yet certified by a device test.
