# SnackUP · Monitoreo administrativo

Propuesta implementada en `test/api-aaa-sonarqube`. El módulo permite al personal autorizado revisar la experiencia de los alumnos por local, carrera, grupo y horario, y registrar acciones de mejora. No modifica `main` ni despliega reglas o datos en Firebase.

## Flujos

1. El alumno califica un pedido completado: experiencia general, servicio y calidad de alimentos (cada dimensión de 1 a 5 estrellas), comentario y carrera/grupo opcionales. Estos últimos datos son autodeclarados, no un padrón escolar verificado.
2. La reseña queda vinculada al pedido y al negocio; el ID del documento es el ID del pedido. Una transacción comprueba propietario, negocio, estado y ausencia de una reseña con ese ID.
3. Una cuenta con el custom claim booleano `admin: true` entra al panel desde el inicio de sesión normal. Cambiar `role` o `admin` en el perfil de Firestore no otorga acceso al panel.
4. El administrador filtra opiniones, compara locales y abre una reseña para registrar responsable, nota y estado: pendiente, en revisión o resuelto. Cada guardado añade un evento al historial. No se envían correos ni amonestaciones automáticas.

## Indicadores y lectura responsable

- Promedio general: suma de las calificaciones generales válidas / número de calificaciones válidas. Se calcula sobre opiniones individuales, no sobre el promedio de promedios de los locales.
- Servicio y alimentos: promedio independiente de cada dimensión; las reseñas históricas sin esa dimensión no aportan cero ni una calificación inventada.
- Opiniones negativas: calificación general de 1 o 2 estrellas. Es una regla explícita de clasificación, no análisis automático del texto.
- Carrera y grupo ausentes: se muestran como `Sin informar`. Los filtros distinguen los registros no informados.
- Se muestra el tamaño de la muestra. Los indicadores describen a quienes dejaron una reseña, no a todos los alumnos de una carrera.
- Horarios y fechas del panel: UTC−6 (campus San Juan del Río). El horario corresponde al envío de la reseña, no necesariamente a la hora de consumo o entrega.
- El panel no muestra nombre, matrícula ni correo del alumno. Un comentario puede contener datos personales escritos por su autor: debe tratarse como información de acceso administrativo.
- Los cuatro nombres y las cifras del modo de demostración son ficticios. En modo conectado los negocios proceden de `businesses`; no se inventan locales para completar cuatro ni se ocultan negocios adicionales.

## Demostración sin Firebase

Desde `app/`, con Flutter 3.32.0:

```bash
flutter pub get
flutter run -d chrome -t lib/main_admin_demo.dart
# Artefacto web local, sin inicializar Firebase:
flutter build web --no-web-resources-cdn -t lib/main_admin_demo.dart -o build/admin-demo
```

La demo utiliza datos en memoria, identificados en pantalla. El HTML deja la carga e inicialización de Firebase a FlutterFire en `main.dart`; no arranca Firebase antes del entrypoint. Las fuentes Inter y Roboto de respaldo están incluidas localmente; para evitar CDN del motor al compilar, usa `--no-web-resources-cdn`. Los seguimientos se conservan durante la sesión de demo y se reinician al recargar. El modo real nunca sustituye errores de permisos o red por datos ficticios.

## Conexión real y límites

El adaptador consulta `businesses`, `reviews` y `admin_followups` en páginas de 200 documentos desde el servidor. Mientras falten páginas, el panel lo indica y permite cargar más. Las gráficas corresponden únicamente a los registros cargados. Una recarga manual vuelve a consultar el servidor; no es una suscripción en tiempo real. El historial muestra hasta 50 eventos y avisa si existen más.

Las reseñas antiguas con ID aleatorio se leen, pero no se migran ni se borran. Antes de enviar, la aplicación busca desde el servidor una reseña propia del mismo pedido y bloquea una segunda valoración; si esa consulta falla, no escribe. El ID determinista garantiza una única reseña nueva por pedido. La comprobación previa no sustituye una migración o deduplicación del conjunto histórico en el servidor.

### Activación pendiente en un entorno aprobado por TI

- Designar las cuentas administrativas y asignar el custom claim desde un entorno de confianza con Firebase Admin SDK. Preservar otros claims existentes; nunca hacerlo desde Flutter ni desde un campo editable por el alumno. Cerrar y volver a iniciar sesión para renovar el token.
- Revisar `tests/api/candidates/admin-monitoring.rules`, que amplía la candidata de pedidos con reseñas y seguimientos. Es una candidata aislada, **no reglas de producción aprobadas**: otras colecciones conservan limitaciones heredadas.
- Probar la candidata en un entorno local/de pruebas aprobado: alumno A no lee reseñas de B, alumno no lee/escribe seguimientos, campo de perfil no concede administración, reseña exige pedido completado y propio, ID único, puntajes 1–5 y validación de tamaños, historial no editable.
- Integrar únicamente los bloques aprobados con las reglas vigentes reales. Firebase aplica las reglas del servidor; ocultar una pantalla no sustituye estas reglas.
- Validar con los cuatro locales reales, cuentas de alumno y administración, y reseñas consentidas. No hay credenciales administrativas ni información real de alumnos en los fixtures.

No se han asignado privilegios, desplegado reglas ni ejecutado escrituras en Firebase de producción durante esta implementación.

## Datos nuevos

`reviews/{orderId}`: `schemaVersion: 2`, `orderId`, `businessId`, `userId`, `rating`, `serviceRating`, `foodRating`, `career`, `group`, `comment`, `createdAt` (timestamp del servidor). Sin `userName` en las reseñas nuevas. Carrera ≤120 caracteres, grupo ≤40, comentario ≤1500. Carrera y grupo vacíos significan no informados.

`admin_followups/{reviewId}` y `history/{eventId}`: `reviewId`, `businessId`, `status` (`pending`, `in_review`, `resolved`), `assignee`, `note`, `updatedAt`, `updatedBy`. La aplicación guarda el estado y el evento en un mismo batch. Responsable ≤120 caracteres y nota ≤2000; ambos obligatorios. La candidata permite estas colecciones sólo al claim administrativo y prohíbe modificar o eliminar los eventos.

## Diseño

Paleta de la referencia `codew.html`: azul `#002654`, lima `#C4D600`, cian `#008BBE`, fondo `#F8F9FA`. Inter está incluida localmente con su licencia OFL. El resto de pantallas conserva el tema existente.

El archivo Figma compartido originalmente no permitía edición a la cuenta conectada. Se creó [SnackUP · Administración](https://www.figma.com/design/NB0QoBVD9RNeUqUHM4JofI), pero la cuota del servicio bloqueó la composición de las pantallas. Ese archivo contiene bases y componentes, no el diseño final validado. El generador nativo en `design/figma-admin/` permite completar las vistas editables desde Figma Desktop; no se ha ejecutado en Figma en esta sesión. La implementación Flutter y sus capturas se validan por separado.

## Fuentes de implementación

- [Firebase: custom claims](https://firebase.google.com/docs/auth/admin/custom-claims).
- [Firebase: condiciones de reglas](https://firebase.google.com/docs/firestore/security/rules-conditions).
- [Cronograma retomado y propuesta de incorporación del módulo](./LINEA_DEL_TIEMPO.md).

## Evidencias de implementación

Consulta [VALIDACION.md](./VALIDACION.md) para resultados de pruebas y límites comprobados.
