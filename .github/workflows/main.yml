name: Build Flutter APK

on:
  workflow_dispatch:
    inputs:
      flutter_version:
        description: 'Flutter version'
        required: true
        default: '3.47.2'

jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - name: Checkout
        uses: actions/checkout@v5

      - name: Setup Gradle Cache
        uses: actions/cache@v5
        with:
          path: |
            ~/.gradle/caches
            ~/.gradle/wrapper
          key: ${{ runner.os }}-gradle-${{ hashFiles('**/*.gradle*', '**/gradle-wrapper.properties') }}
          restore-keys: |
            ${{ runner.os }}-gradle-

      - name: Setup Java 17
        uses: actions/setup-java@v5
        with:
          distribution: temurin
          java-version: '17'

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ github.event.inputs.flutter_version }}
          cache: true
          channel: stable

      - name: Get dependencies
        run: flutter pub get

      - name: Build APK
        run: flutter build apk --release

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: app-release
          path: build/app/outputs/flutter-apk/app-release.apk
          if-no-files-found: error
          retention-days: 7
