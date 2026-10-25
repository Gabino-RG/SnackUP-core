# SnackUP · cliente de alumnos

Rama `codex/cliente-campus`. La aplicación activa utiliza la API FastAPI de `codex/backend-api-v3-fastapi` (`1c3459b`), con azul marino, lima y celeste. No incorpora pantallas de personal.

**Firebase queda aparte:** no se importaron datos, no se cambiaron reglas ni se publicaron modificaciones en `snackup-8fe96`. El cliente activo no inicializa Firebase ni lee/escribe Firestore. La implementación anterior se conserva como texto de referencia en `legacy/firebase/`.

## Ejecutar con la API

Las cuentas, productos y pedidos deben existir en la base SQL del backend; una cuenta de Firebase no se convierte automáticamente en una cuenta de la API. El backend necesita su configuración, migraciones, padrón y correo según las instrucciones de su propia rama.

### Web, un mismo origen

Con Flutter instalado:

```shell
flutter pub get
flutter build web --pwa-strategy=none
```

Para desarrollo local, iniciar el backend por separado en `http://127.0.0.1:8000`, con `SNACKUP_PUBLIC_ORIGIN=http://localhost:8080`. Después, con **Node.js 20 o posterior**:

```shell
node tools/serve_api_web.mjs --backend=http://127.0.0.1:8000 --port=8080
```

Abrir `http://localhost:8080`. El proxy sirve `build/web`, `/api/*`, `/media/*` y Socket.IO bajo el mismo origen, necesario para las cookies y los permisos de origen. Este servidor es solo para desarrollo local; producción debe usar HTTPS y el proxy de despliegue del backend. No se necesita publicar nada en Firebase.

La API predeterminada de web es `/api/v1/` en el mismo sitio. Una dirección explícita se configura al compilar:

```shell
flutter build web --pwa-strategy=none --dart-define=API_BASE_URL=https://tu-dominio/api/v1/
```

El dominio es un ejemplo, no una API desplegada. Mantener frontend y API en el mismo origen. `API_BASE_URL` cambia el destino HTTP, no configura CORS ni el origen autorizado del servidor.

### App nativa

```shell
flutter run --dart-define=API_BASE_URL=https://tu-dominio/api/v1/
```

En el emulador Android, desarrollo puede utilizar `http://10.0.2.2:8000/api/v1/`. HTTP se permite solo en el manifiesto de depuración de Android. Producción requiere HTTPS. Los builds nativos no se han validado en un dispositivo real en esta entrega.

## Comprobación

```shell
flutter analyze --no-fatal-infos
flutter test
flutter test --platform chrome test/api_integration_test.dart
```

Ver [integración, compatibilidad y límites](docs/integracion-api.md), [contrato fijado](docs/api/backend-v3.openapi.json) y [prueba local del backend](docs/evidence/api-client/backend-smoke.json).

Los cambios se revisan en ramas y mediante PR; no hacer push directo ni fusionar en `main` o `develop`.
