# SnackUP Sprint 10

Aplicación móvil Flutter para pedidos de cafetería universitaria. Incluye acceso de estudiante y negocio, menú, carrito, pedidos y entrega mediante QR por pedido.

## Estado de la entrega

Versión preparada: **1.0.0+10**. Base: `sprint9`, commit `04865e07e4cd7a2068c183b44741c915894a5623`.

Se aprobaron 23 pruebas Flutter y 40 comprobaciones de Firestore en el emulador local el 27 de noviembre de 2026. La instalación y el recorrido completo en Android con Firebase publicado deben quedar registrados antes de entregar. El APK debe descargarse del workflow o generarse localmente; el código fuente por sí solo no sustituye al APK.

## Política de integración del equipo

Prohibido hacer push directo a `main` o `develop`. Integrar mediante pull request y al menos una aprobación de un socio. Esta preparación utiliza la rama `codex/sprint10-entrega`, sin fusionar automáticamente.

## Entorno probado

- Flutter 3.32.4 y Dart 3.8.1. `pubspec.yaml` exige Dart ^3.8.0.
- Android: minSdk 23, compileSdk y targetSdk 36; NDK 27.0.12077973.
- Java 17 para compilar Android; Java 21 usado en el emulador Firestore local.
- Node 22 o superior para las pruebas de Firestore y Firebase CLI.

## Preparación

```powershell
flutter pub get
flutter analyze --no-fatal-infos
flutter test --reporter expanded
flutter build apk --release --build-name=1.0.0 --build-number=10
```

La salida será `build/app/outputs/flutter-apk/app-release.apk`. El build release conserva la **firma debug para demostración académica**. Para distribución de producción se necesita una clave propia y conservarla de forma privada. No incluir `.jks`, `.keystore` ni `android/key.properties` en Git.

La configuración cliente de Firebase usa el proyecto **snackup-8fe96** y el paquete `com.example.snackup`. `android/app/google-services.json` contiene únicamente la configuración pública equivalente a `lib/firebase_options.dart`. Las claves cliente no conceden acceso administrativo; la autorización se implementa con Auth y Rules. Si se cambia de proyecto, regenerar ambos mediante FlutterFire de forma coherente. No seleccionar el nombre antiguo snackup-official por error.

## Pruebas Firestore con datos ficticios

```powershell
firebase emulators:exec --only firestore --project demo-snackup-sprint9 "node test/firestore_sprint9.mjs"
```

El script solo permite localhost y usa un proyecto `demo-`. No ejecutarlo contra la base real. Si una versión antigua del emulador falla por el idioma Java, iniciarlo con `-Duser.language=en -Duser.country=US`. La bitácora detalla la versión ejecutada.

Las reglas e índices del repositorio **no demuestran estar desplegados**. Probarlos en un proyecto de prueba y revisar las cuentas de demostración antes de publicar cambios de backend. La eliminación de productos nueva requiere la regla `allow delete` del propietario; con reglas antiguas puede recibir permission-denied.

## Descargar el APK desde GitHub Actions

El workflow `.github/workflows/android-apk.yml` se ejecuta al cambiar código en `codex/**`, y también permite ejecución manual. Compila con Flutter 3.32.4, analiza, ejecuta pruebas y verifica la firma. En una ejecución aprobada, descargar el artefacto `SnackUP-Android-1.0.0-build10-*`, extraer el APK y su SHA256, e instalar ese mismo archivo en el teléfono. El artefacto se conserva 30 días; Scrum Master debe subir el APK a la asignación, no solo el enlace temporal de Actions.

```powershell
adb install -r "SnackUP-1.0.0+10.apk"
Get-FileHash "SnackUP-1.0.0+10.apk" -Algorithm SHA256
```

## Arquitectura implementada

`lib/features/{auth,home,user,business}` agrupa pantallas por función; `lib/theme` comparte estilos; `lib/services/weather_service.dart` separa la API climática. Widgets gestionan estado local con setState y observan datos con StreamBuilder/FutureBuilder. Muchas pantallas acceden directamente a Firebase. Provider está declarado, pero no se usa como patrón de estado; no afirmar MVVM ni una capa completa de repositorios.

WeatherService permite inyectar HTTP, reloj y timeout. Consulta Open-Meteo con coordenadas fijas del campus; no envía nombre, correo ni GPS del estudiante. Caché en memoria 15 minutos y fallback menor de una hora. Ante fallo conserva el menú y una sugerencia general.

## Roles y demostración

El registro crea rol `user` con correo @utsjr.edu.mx. Una cuenta de negocio debe ser asignada por el administrador autorizado con `users/{uid}.role = business` y `businesses/{businessId}.ownerId = uid`. Elegir el acceso Negocio no concede permisos.

El QR utiliza `snackup:order:<orderId>` y se compara con el pedido abierto. El código manual es el ID completo. Es una referencia del pedido, no una credencial secreta; Rules restringe las transiciones al dueño del negocio.

Permisos declarados: internet, cámara y notificaciones. Los avisos actuales del negocio utilizan Firestore y sonido dentro de la aplicación activa. No se acredita un backend de notificaciones push para app cerrada.

## Documentación y pendientes de cierre

- `docs/sprint10.json`: contenido de documentación y matriz de requisitos.
- `docs/PRUEBAS_Y_CIERRE.txt`: resultados, casos manuales y checklist.
- `docs/evidencias/`: registros reales de Flutter y Firestore.

Completar integrantes, grupo, Scrum Master, arquitectura elegida previamente, fecha asignada y documentos de sprints anteriores. Todos deben asistir presencialmente y puntuales el 1 o 3 de diciembre según la asignación del grupo. Solo Scrum Master sube APK y documentación; los demás marcan entregada.

Limitaciones: el stock se valida pero no se descuenta ni reserva automáticamente; no se verifica propiedad del correo institucional con emailVerified; Tarjeta/Vale son selección del pedido, sin pasarela de pago integrada; no se ha demostrado cifrado de extremo a extremo ni cifrado propio de campos. Firebase proporciona protección de transporte y cifrado administrado de su servicio, que debe describirse con precisión.
