# Conexión de Cocina y Administración con el backend entregado

Alcance acordado el 26 de octubre de 2026: conectar y validar las pantallas
actuales. No incorpora pantallas nuevas de chat, cierres programados, liberación
de vales ni cancelación por pedido no recogido.

## Versiones y rutas

- Frontend: rama `codex/entrega-paneles-rest`, entrada `app/lib/main_portal_api.dart`.
- Backend: [81c76c5eda9ba6315fbf1dcd1a69599f8906db5e](https://github.com/Gabino-RG/SnackUP-core/commit/81c76c5eda9ba6315fbf1dcd1a69599f8906db5e),
  de `codex/auditoria-v32-contenedor-unico`.
- Portal desplegado en `/paneles/`; API `/api/legacy/v1/`; WebSocket nativo
  `/api/legacy/v1/realtime`. Servirlos desde el mismo origen HTTPS.
- `/api/v1/` es la API canónica para alumnos y nuevas funciones. Sus roles y
  estructuras difieren: no cambiar únicamente el prefijo del portal.
- `docs/integracion/openapi.json` coincide en `paths` y `components` con
  `backend/contracts/panels.openapi.json` de esa revisión. La prueba comprueba
  esta igualdad antes de arrancar.

El backend conserva separados sus fuentes y los del portal. Esta integración no
modifica la rama de backend ni `respaldo/2026-10-13-antes-restablecimiento`.

## Ajustes de compatibilidad

Administración admite opiniones de **0–5 estrellas**: cero cuenta en el promedio,
el histograma, la tendencia y las alertas de 0–2 estrellas. Una dimensión ausente
sigue siendo desconocida, sin convertirla en cero. Se actualizó el esquema de
respuesta Review del contrato a la versión entregada.

El catálogo explica el límite de tres destacados cuando el servidor rechaza un
cuarto. Cocina muestra un mensaje específico si el vale del pedido pertenece a
otro día y el backend impide entregarlo.

## Prueba reproducible contra el backend real

Desde una copia del frontend, con Flutter 3.32.0, Python 3.12 y Node instalados:

```sh
git worktree add --detach ../SnackUP-backend-v32 81c76c5eda9ba6315fbf1dcd1a69599f8906db5e
python -m venv .venv
# Activar .venv según el sistema operativo.
python -m pip install -r ../SnackUP-backend-v32/backend/requirements.lock
cd app
flutter pub get
flutter test
flutter build web --release --target lib/main_portal_api.dart --base-href /paneles/ --pwa-strategy=none --no-web-resources-cdn
cd ..
python scripts/integration/live_backend.py --backend ../SnackUP-backend-v32/backend
```

Para comprobar además el navegador, instalar Playwright/Chromium, definir
`SNACKUP_PLAYWRIGHT` con la ruta del paquete y ejecutar el último comando con
`--web app/build/web`. Si Flutter o Node no están en PATH, usar `--flutter` y
`--node`. El workflow `Entrega de paneles REST`, trabajo `backend-v32`, ejecuta
ambas pruebas y guarda capturas y resultados como artefactos.

El runner inicia **FastAPI real y una base SQLite temporal**, crea únicamente
cuentas sintéticas con contraseña aleatoria y escucha en loopback. No acepta una
URL de servidor remoto ni una base existente. El backend debe estar sin cambios
y en el commit fijado. No imprime credenciales ni guarda tokens en las evidencias.

Los clientes Dart reales comprueban:

- Inicio de sesión, perfil, renovación y cierre de sesión.
- Catálogo: consulta, alta, edición, eliminación y límite de destacados.
- Compra canónica, repetición idempotente y lectura desde Cocina legacy.
- Aceptar, preparar, marcar listo, rechazar un código incorrecto y entregar.
- Conflicto de versión y aislamiento entre locales y Administración.
- Cancelación, historial y cierre manual del local.
- Opinión de cero estrellas del alumno, carrera del padrón y seguimiento administrativo.

El navegador usa el portal compilado en `/paneles/`: comprueba acceso de Cocina,
restauración de sesión después de recargar con la cookie real del navegador,
recepción de un pedido por WebSocket y aceptación desde el tablero,
historial, cierre de sesión, acceso de Administración y opinión visible. Guarda
capturas de escritorio y móvil en `build/live-backend/`.

## Límites de esta validación y despliegue

Validación local de esta entrega: 115 pruebas Flutter aprobadas, compilación web
de producción correcta y 27 pruebas del simulador/contrato aprobadas (260
respuestas). El analizador no encontró errores; conserva avisos de estilo y dos
imports sin uso ya existentes. La prueba adicional con FastAPI descrita arriba
es independiente del simulador y produce su propio resultado del navegador.

Esta prueba de compatibilidad no mide concurrencia, Redis entre workers,
SMTP, certificados, lectura de QR por cámara física ni la capacidad de mil
alumnos simultáneos. Esas comprobaciones requieren el entorno correspondiente.
Las pruebas unitarias/widgets y el navegador complementan, no sustituyen, las
pruebas PostgreSQL y del contenedor realizadas por el equipo del backend.

El contenedor unificado del backend actualmente fija el frontend anterior
`19c81fdee29600d66d9dcb1a4f109a78aeba51f6`. Para publicar estos ajustes, el equipo
debe actualizar la referencia del contexto de paneles al commit de esta entrega,
reconstruir y ejecutar su smoke test del contenedor. Subir esta rama por sí solo
no actualiza un servidor ni cambia ese contexto fijado.

Configurar `SNACKUP_PASSWORD_RESET_FRONTEND_PATH=/paneles/` para que los enlaces
de recuperación del portal vuelvan a la subruta correcta; confirmar también
dominio, HTTPS, SMTP y padrón institucional antes del acceso real.
