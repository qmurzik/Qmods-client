# QMods Android Client

Production-ready native Android client for the QMods service, built with Kotlin, Jetpack
Compose (Material 3) and a clean MVVM architecture.

## Stack

- Kotlin, Jetpack Compose (Material 3), Navigation Compose
- MVVM + Clean Architecture (`data` / `domain` / `presentation` / `di`)
- Coroutines + Flow
- Retrofit + OkHttp, kotlinx.serialization
- DataStore (Preferences) for the session token
- Hilt for dependency injection
- `androidx.core:core-splashscreen` for the splash screen

## Project structure

```
app/src/main/java/ru/qmods/client/
├── data/
│   ├── api/         Retrofit service + AuthInterceptor (Bearer header, 401 -> logout)
│   ├── local/        SessionManager (DataStore-backed session token + device id)
│   ├── mapper/       DTO -> domain model mappers
│   ├── model/        Retrofit/kotlinx.serialization DTOs
│   ├── repository/   Repository implementations
│   └── util/         safeApiCall (connectivity + HTTP/error handling shared by every repo)
├── domain/
│   ├── model/         Plain domain models
│   ├── repository/    Repository interfaces
│   ├── usecase/       One class per use case
│   └── util/          Resource<T> / ErrorType
├── presentation/
│   ├── components/    Reusable Compose UI (cards, buttons, skeletons, dialogs, states)
│   ├── navigation/     NavGraph, bottom bar, session-driven auto-logout redirect
│   ├── screens/        One package per screen, each with its own ViewModel
│   └── theme/          Color/Type/Shape/Theme, dark-only premium palette
└── di/                Hilt modules (network, DataStore, repositories, coroutine scope)
```

## Talking to the PHP API

Base URL: `https://qmods.ru/api/` (see `BuildConfig.API_BASE_URL`, defined in
`app/build.gradle.kts`). Every endpoint in `QModsApiService` is expressed as a path appended
to `client_api.php`, e.g. `client_api.php/profile`, matching the endpoint names given in the
spec. **If the real backend instead expects `client_api.php?action=profile`-style routing,
only the `@GET`/`@POST` path strings in `QModsApiService.kt` need to change** — nothing else
in the app depends on the routing style.

Response DTOs (`data/model/*.kt`) were modeled from the field names in the spec (e.g.
`session_token`, `active`, `plan_name`, `expires_at`, `days_left`, `device_id`, `is_read`,
...). The JSON parser is configured with `ignoreUnknownKeys = true`, `coerceInputValues = true`
and `isLenient = true`, so extra/missing fields and numbers sent as quoted strings by PHP won't
crash parsing — but **field *names* that differ from the spec will need matching `@SerialName`
updates** in the DTOs.

Every repository call goes through `safeApiCall()`, which:
1. Checks connectivity first and returns a friendly "no internet" error without hitting the
   network if there's none.
2. Maps HTTP 401 to `ErrorType.SESSION_EXPIRED`.
3. Maps other non-2xx / thrown exceptions to `ErrorType.SERVER` / `UNKNOWN` with a message.

`AuthInterceptor` attaches `Authorization: Bearer <token>` to every request except `login`,
and on any 401 clears the stored session. `SessionViewModel` (bound into `QModsNavGraph`)
observes the session and redirects to the login screen the moment it becomes invalid —
whether that's a manual logout or a background 401 — so there's a single source of truth
for "am I logged in" across the whole app.

## Certificate pinning

`network_security_config.xml` blocks cleartext traffic. SSL pinning itself is wired up in
`di/NetworkModule.kt` via OkHttp's `CertificatePinner`, driven by `Constants.CERTIFICATE_PINS`
(`util/Constants.kt`) — **left empty by default**. An empty pin list means the pinner isn't
attached at all, so the app relies on normal system CA trust until you fill in the real pins:

```
openssl s_client -connect qmods.ru:443 -servername qmods.ru < /dev/null 2>/dev/null | \
  openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | \
  openssl dgst -sha256 -binary | openssl enc -base64
```

Add both the leaf pin and a backup (issuing CA or a second key) so rotating the certificate
doesn't lock the app out of its own API.

## Building

```
./gradlew assembleDebug     # debug APK
./gradlew assembleRelease   # release APK (minified, shrunk)
```

Requires an Android SDK with platform 35 installed (`compileSdk`/`targetSdk` = 35, `minSdk` =
26) — set `ANDROID_HOME`/`local.properties` as usual for Android Studio.

> **Note on this build's provenance:** this project was generated and reviewed in a sandboxed
> environment without network access to Google's Maven repository (`dl.google.com` /
> `maven.google.com`), so AGP, the Android SDK and the AndroidX/Compose artifacts could not be
> downloaded to run an actual `./gradlew assembleDebug` here. Every file was written and then
> re-read against Compose/Hilt/Retrofit/Kotlin APIs from memory, with a dedicated review pass
> that caught and fixed several real issues (a missing `@ApplicationContext` qualifier, a
> couple of missing `getValue` imports for `by` delegates, a broken `BuildConfig` string
> template). Please run a full build in Android Studio as the first step and treat that as the
> actual verification — file an issue/ping back with any compiler errors and they can be
> fixed directly.

## Design

Dark-only "premium fintech / game launcher" look: deep navy backgrounds, a violet-to-cyan
brand gradient, soft-bordered cards, pill status badges, shimmering skeleton loaders instead
of spinners, and pull-to-refresh on every list/detail screen.
