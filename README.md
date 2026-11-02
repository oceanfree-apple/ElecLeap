# ElecLeap iPhone

Flutter 3.38.10 companion for the ElecLeap e-paper photo frame, version 0.4.0.

Cream surfaces, black frames and pills, muted gold accents. Includes account registration/login and Keychain sessions, photo crop with simultaneous two-finger rotation/zoom/pan, one-step upload/display, device-confirmed refresh progress, scrolling thumbnail/large albums, tags, slideshow, device sharing, widgets, gallery/community, and manual drawing. BLE uses native CoreBluetooth with the same authenticated EL1 HMAC/HKDF/AES-GCM protocol as the mini-program and ESP32 firmware. AI/voice entrances remain inactive.

The public app contains no cloud login token, WiFi password, device key or Apple credentials. The HTTPS service address is public configuration; users authenticate normally. A one-time linking code from the mini-program can connect an empty iPhone account to the existing WeChat owner.

`flutter pub get --enforce-lockfile`, `flutter analyze`, `flutter test`.

GitHub Actions builds an **unsigned arm64 Release IPA** on macOS. Download the `ElecLeap-iPhone` artifact from the successful run, verify `SHA256SUMS`, then sign and install locally through the previously configured Ubuntu iloader workflow. An unsigned IPA cannot install by simply tapping it on iPhone. Apple login and any device trust/developer-mode prompts stay local. No Apple account is sent to CI. Use the same bundle ID and Apple team for subsequent updates.

The repository's tests exercise geometry, protocol compatibility and Flutter layout. Native iOS permission prompts, physical Bluetooth radio, signing and installation require a real iPhone and are recorded separately from these checks.
