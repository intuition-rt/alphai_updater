# Alphai Robot Firmware Updater

A Flutter Web application designed to flash firmware onto Alphai robots directly from the browser using the Web Serial API.

## Features

- 🔌 **Web Serial Integration**: Connect to ESP32-based robots directly via USB in the browser.
- 🚀 **Firmware Flashing**: Updates Bootloader, Partition Table, and Application firmware.
- 🎨 **Modern UI**: Features smooth animations, dark/light mode support, and a responsive design.
- 📊 **Progress Tracking**: Real-time progress bars for different stages of the flashing process.

## Requirements

- A browser with **Web Serial API** support (Chrome, Edge, Opera). *Firefox and Safari are not currently supported.*
- USB cable to connect the Alphai Robot.
- [Optional] FTDI Adapter if required by your specific board version.

## Development

### Setup

1.  **Install Flutter**: Ensure you have the Flutter SDK installed.
2.  **Enable Web Support**:
    ```bash
    flutter config --enable-web
    ```
3.  **Get Dependencies**:
    ```bash
    flutter pub get
    ```

### Run Locally

```bash
flutter run -d chrome
```

## Deployment

This project is configured to deploy automatically to GitHub Pages using GitHub Actions.

The build workflow performs:
1.  Sets up the Flutter environment.
2.  Builds the project for web (`flutter build web --release`).
3.  Uploads the artifact to GitHub Pages.

**Note on Base Href:**
If deploying to a project page (e.g., `username.github.io/repo-name`), you may need to adjust the `base-href` in the build command within `.github/workflows/deploy.yml`:

```yaml
run: flutter build web --release --base-href "/repo-name/"
```
