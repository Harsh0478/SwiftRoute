# SwiftRoute — Package Delivery & Logistics Platform

## Setup Instructions

### 1. Environment Configuration (`.env`)
Create a `.env` file inside both `customer_app/` and `partner_app/` (see `.env.example` in each folder):
```env
MAPBOX_ACCESS_TOKEN=your_mapbox_public_token
API_BASE_URL=http://10.0.2.2:5000/api
SOCKET_URL=http://10.0.2.2:5000
```
- For **Android Emulator**, keep `10.0.2.2`.
- For a **Physical Phone** on the same Wi-Fi, set `API_BASE_URL` and `SOCKET_URL` to your PC's IPv4 address (e.g., `http://192.168.1.15:5000/api`).
- Add your Mapbox downloads token to `customer_app/android/gradle.properties` and `partner_app/android/gradle.properties` (`MAPBOX_DOWNLOADS_TOKEN=...`).

### 2. Backend (`server/`)
```bash
cd server
npm install
npm run dev
```

### 3. Customer App (`customer_app/`)
```bash
cd customer_app
flutter pub get
flutter run --dart-define-from-file=.env
```

### 4. Delivery Partner App (`partner_app/`)
```bash
cd partner_app
flutter pub get
flutter run --dart-define-from-file=.env
```

### 5. Admin Web Dashboard (`admin_web/`)
```bash
cd admin_web
flutter pub get
flutter run -d chrome --web-port 8080
```
