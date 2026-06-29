# Metrix Client

Cliente de rastreo GPS para Android e iOS, construido sobre Flutter. Corre en segundo plano y envía actualizaciones de ubicación a tu propio servidor [Traccar](https://www.traccar.org/). Es un fork privado del cliente oficial de Traccar, orientado a confiabilidad en operaciones de campo (diagnósticos, watchdog y monitoreo de salud).

## Características

- **Rastreo en tiempo real** — la ubicación del dispositivo se ve en tu servidor privado al instante.
- **Segundo plano** — usa `flutter_background_geolocation` para reportar incluso con la pantalla apagada.
- **Privacidad** — los datos van solo a tu servidor; nunca a terceros.
- **Configurable** — intervalo de actualización, precisión y uso de datos ajustables.
- **Diagnósticos** — pantalla de salud (health screen) y caché local de ubicaciones para resiliencia de red.
- **Notificaciones push y QR** — provisión rápida vía código QR y mensajería Firebase.

## Stack y versiones

| Componente | Versión |
|---|---|
| Flutter | 3.44.0 (stable) |
| Dart SDK | 3.12.0 (requiere `sdk: ^3.7.2`) |
| App version | 9.7.20+137 |
| Application ID | `org.traccar.client` |

Dependencias principales (ver [`pubspec.yaml`](pubspec.yaml) para la lista completa):

- `flutter_background_geolocation: ^5.2.0` — rastreo en segundo plano
- `firebase_core / messaging / analytics / crashlytics` — Firebase
- `shared_preferences: ^2.5.5` — configuración local
- `flutter_secure_storage: ^10.2.0` — almacenamiento seguro
- `mobile_scanner: ^7.2.0` — lectura de QR
- `permission_handler: ^12.0.0` — permisos
- `flutter_local_notifications: ^19.5.0` — notificaciones locales

## Requisitos previos

- **Flutter SDK** 3.44.0 o superior ([instalación](https://docs.flutter.dev/get-started/install))
- **Android Studio** / Android SDK para compilar Android
- **Xcode** (solo macOS) para compilar iOS
- **Firebase** — un proyecto configurado. Los archivos `firebase_options.dart`, `google-services.json` (Android) y `GoogleService-Info.plist` (iOS) deben estar presentes.

Verifica tu entorno con:

```bash
flutter doctor
```

## Cómo correrlo

```bash
# 1. Instalar dependencias
flutter pub get

# 2. Generar localizaciones (l10n)
flutter gen-l10n

# 3. Correr en un dispositivo o emulador conectado
flutter run

# Para una build de release:
flutter build apk          # Android (APK)
flutter build appbundle    # Android (AAB para Play Store)
flutter build ios          # iOS (requiere macOS + Xcode)
```

Lista los dispositivos disponibles con `flutter devices`.

## Configuración de la app

Al iniciar, ingresa la **dirección del servidor** Traccar, otorga los **permisos de ubicación** (incluido "permitir siempre" para segundo plano) y la app comenzará a enviar reportes periódicos automáticamente.

## Estructura del proyecto

```
lib/
├── main.dart                   # Punto de entrada
├── main_screen.dart            # Pantalla principal
├── settings_screen.dart        # Configuración
├── status_screen.dart          # Estado del rastreo
├── health_screen.dart          # Diagnósticos / salud
├── qr_code_screen.dart         # Provisión por QR
├── geolocation_service.dart    # Servicio de ubicación
├── configuration_service.dart  # Configuración persistente
├── notification_service.dart   # Notificaciones
├── push_service.dart           # Firebase push
├── health_service.dart         # Watchdog / monitoreo
├── location_cache.dart         # Caché local de ubicaciones
└── l10n/                        # Localizaciones
```

## CI

El repositorio incluye workflows de GitHub Actions en [`.github/workflows`](.github/workflows): `analyze.yml` (análisis estático), `release.yml` (builds de release) y `translation.yml` (sincronización de traducciones).

## Licencia

Apache License, Version 2.0. Ver [`LICENSE.txt`](LICENSE.txt).
