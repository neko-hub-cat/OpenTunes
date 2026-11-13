# OpenTune

Privacy-first offline Android music player.

## Implemented in this branch
- Kotlin MediaStore audio scan using Android's scoped media APIs.
- Android 13+ audio permission and legacy storage permission request.
- Local content URIs played through just_audio (Android ExoPlayer backend).
- audio_service media session and foreground notification controls.
- Play/pause, previous/next, seek bar, search, album and artist grouping.
- Empty-library, scan and permission-error states.

## Architecture
- Flutter/Dart: UI and app state.
- Kotlin: MediaStore scanner and SDK bridge.
- just_audio: audio decoding/playback.
- audio_service: Android media session, background service and notification actions.
- Rust is not bundled yet: an unused Rust runtime/FFI layer would add binary and build complexity without helping basic scanning or playback. Consider it only for benchmarked CPU-heavy extras such as waveform analysis.

## Verify on Android
```sh
flutter pub get
flutter analyze
flutter run
```
Test on a physical device for Android 13+ permissions, local MP3/AAC/FLAC, lock-screen and notification buttons, headset controls, audio focus and pause/resume.
