# SwiftRoute — Package Delivery & Logistics Platform (v3 - Mapbox Edition)

## What's Included in v3
- **Mapbox Maps & Geocoding v6 Integration (`customer_app/`)**:
  - **Real-Time Address Autocomplete**: Debounced Mapbox Geocoding v6 (`/search/geocode/v6/forward`) search in the Booking Wizard for both Pickup and Delivery addresses.
  - **Interactive Pin-Drop Map Picker & Current GPS**: Tap **Pin on Map** to pan/tap anywhere on a live Mapbox map with automatic reverse geocoding (`/search/geocode/v6/reverse`), or tap **Use Current GPS**.
  - **Live Mapbox Tracking (`LiveTrackingScreen`)**: Interactive Mapbox Streets vector map with pickup, live courier, and destination markers, orange route polyline, real-time Socket.IO location tracking, and a draggable bottom sheet (`DraggableScrollableSheet`).
- **Backend (`server/`)**:
  - Default shipment status set to `Assigning Courier...` until accepted/updated by a delivery partner.
- **Stability & Android Fixes**:
  - `flutter_secure_storage: ^9.2.4` with `encryptedSharedPreferences: true`.
  - `android:usesCleartextTraffic="true"` for local IPv4 testing on physical phones.
  - `kotlin.incremental=false` in `android/gradle.properties` for Windows builds.
  - Runtime location permission prompts and "No Orders Found" empty states.

---

## Setup Instructions

### 1. Mapbox Tokens (Required for Android Map & Address Search)
1. Sign in at [account.mapbox.com](https://account.mapbox.com/).
2. Copy your **Default public token** (`pk.eyJ1...`) and paste it into:
   - `customer_app/lib/core/constants/api_constants.dart` (`mapboxPublicToken`)
   - `partner_app/lib/main.dart` (`mapboxPublicToken`)
3. Create a **Secret token** (`sk.eyJ1...`) with the **`Downloads:Read`** scope enabled, and paste it into:
   - `customer_app/android/gradle.properties` (`MAPBOX_DOWNLOADS_TOKEN=sk....`)
   - `partner_app/android/gradle.properties` (`MAPBOX_DOWNLOADS_TOKEN=sk....`)

### 2. Backend (`server/`)
```bash
cd server
cp .env.example .env
# Add MONGO_URI, JWT secrets, and optional Razorpay / Firebase credentials in .env
npm install
npm run dev
```

### 3. Customer App (`customer_app/`)
- For **Android Emulator**, keep `10.0.2.2` in `customer_app/lib/core/constants/api_constants.dart`.
- For a **Physical Phone** on the same Wi-Fi, replace `10.0.2.2` with your PC's IPv4 address (e.g., `192.168.1.15`).
```bash
cd customer_app
flutter clean
flutter pub get
flutter run
```

### 4. Delivery Partner App (`partner_app/`)
```bash
cd partner_app
flutter clean
flutter pub get
flutter run
```

### 5. Admin Web Dashboard (`admin_web/`)
```bash
cd admin_web
flutter pub get
flutter run -d chrome --web-port 8080
```
