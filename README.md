# SoundMeter Pro — Xcode starter with premium UI assets

**Minimum deployment target:** iOS 17.0  
**Stack:** SwiftUI, SwiftData, AVFoundation, UIKit share sheet  
**Bundle ID:** `com.example.SoundMeterPremium` (change before distribution)

## Included screens
- Live meter with animated gauge, current/average/minimum/maximum digital levels, trend graph and recording controls
- Spectrum preview screen
- Searchable history
- Session details, notes, graph and CSV export
- Reports list with CSV share actions
- Calibration profile storage UI
- Appearance and measurement settings
- Pro paywall preview
- App icon asset and UI showcase image

## Open
Open `SoundMeter.xcodeproj`, select the SoundMeter scheme, choose an iOS 17+ simulator or physical iPhone, set a signing team, then run. Microphone access requires a physical device for meaningful testing.

## Important limitations
This is an expanded starter project, not a verified App Store-ready product. The live level is **dBFS**, not calibrated dB SPL. A/C/Z weighting filters are not implemented, and the weighting picker is a preference UI only. Calibration profiles are stored but not applied to live results. The spectrum bars are illustrative, not live FFT output. CSV export is implemented; PDF export, StoreKit 2 purchases, iCloud sync, widgets, Live Activities and Apple Watch are not implemented.

The generated UI showcase image is a design reference, not a set of production screenshots. Validate compilation in Xcode and compare measurement output against a suitable reference instrument before making accuracy claims.
