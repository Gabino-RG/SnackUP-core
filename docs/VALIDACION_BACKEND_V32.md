# Validación final del backend SnackUP V3.2

Fecha: 23 de octubre de 2026. Entrega en el
[PR #25](https://github.com/Gabino-RG/SnackUP-core/pull/25).

Código y pruebas: `bcaee365462b80afc9c4740d9be60cbc3262cd41`.
Árbol probado: `a500691ebc9744771e14dfa15fde5c2134d67f61`.
Los commits posteriores que agregan este informe solo documentan evidencia.

## Alcance implementado y compatibilidad

El backend incorpora las 15 operaciones antes ausentes del documento V3.2 y
sus reglas asociadas: carrito, favoritos, búsqueda, destacados, programación,
cierres y postergaciones, vales, calificaciones 0–5, chat efímero y avisos. También
añade historial privado, estadísticas detalladas y extensiones administrativas.
El inventario pasa de 55 a **78 operaciones canónicas**, sin quitar rutas previas
de V3 o `/api/legacy/v1`. La prueba de inventario verifica ambas inclusiones.

Alembic `0003_v32` conserva las 23 tablas anteriores y añade seis. Las pruebas
parten de bases pobladas en `0001_initial` y `0002_v3`, migran hasta head y
comparan todas las columnas históricas. No se ejecutaron cambios en bases reales.

Las solicitudes anteriores de reseñas se conservan; el nuevo cuerpo `stars`
comparte una sola calificación por pedido con `/rating`. El catálogo legacy
también respeta el límite de tres destacados. Usuarios, pedidos, sesiones,
padrón, reseñas, auditoría y seguimientos permanecen en el esquema existente.

## Resultados reproducibles

| Verificación | Resultado | Evidencia |
|---|---|---|
| Regresión local, Redis y Caddy reales | 235 aprobadas, 32 omitidas por PostgreSQL; cero fallos | [Resumen local](evidence/v32-bcaee365/local-summary.json) |
| Suite con PostgreSQL 17 y Redis | 261 aprobadas, 6 omitidas por Caddy local; cero fallos | [Workflow backend](https://github.com/Gabino-RG/SnackUP-core/actions/runs/40015736002) |
| Migraciones PostgreSQL y metadata | Alembic upgrade/check aprobados | Mismo workflow backend |
| Referencias y estilo | Ruff, OpenAPI y Prisma aprobados; 29 modelos y 54 relaciones SQL | Mismo workflow backend |
| Compilación de ambas PWA e imagen unificada | Aprobada; ejecución sin root | [Workflow del contenedor](https://github.com/Gabino-RG/SnackUP-core/actions/runs/40015736127) |
| HTTP, assets, rutas y Socket.IO | 27 comprobaciones aprobadas | [smoke.json](evidence/v32-bcaee365/smoke.json) |
| Recuperación tras detener Redis | Reinicio completo, estado saludable y otras 27 comprobaciones aprobadas | [smoke-after-restart.json](evidence/v32-bcaee365/smoke-after-restart.json) |

Las seis omisiones de CI requieren un ejecutable Caddy en ese job; esos casos
pasaron en la suite local y el workflow unificado prueba Caddy dentro de Docker.
[Resumen PostgreSQL](evidence/v32-bcaee365/postgres-summary.json).

Las pruebas incluyen permisos por rol/propietario, privacidad del chat en Socket.IO,
eliminación de mensajes y rechazo de eventos pendientes de chats cerrados,
calificaciones cero, idempotencia, rollback de vale/stock/consecutivo, medianoche,
cancelación por no recogida, cierres tras reiniciar y alertas sin duplicados.
El reloj se comprueba después de adquirir los bloqueos del pedido, de modo que
una espera no permita comprar después del cierre o con menos de cinco minutos
de anticipación para la recogida.

Las carreras nuevas se ejercitan con PostgreSQL real: vale global entre negocios,
cuarto destacado entre clientes V3 y legacy, apertura simultánea de chat,
dos procesos de tareas y entrega contra cancelación del mismo pedido.

## Contenedor y límites de la entrega

Compose mantiene exactamente `app` y `db`. Una sola imagen de aplicación reúne
FastAPI, las dos PWA, Caddy, Redis privado por socket Unix y el proceso de tareas.
PostgreSQL conserva su servicio y volumen independientes, sin publicar su puerto.
Las PWA se compilan desde los mismos commits fijados en la validación anterior:
alumnos `a00d0bf4ecdae74a89f3afbe8ec3d0758efb8884` y paneles
`19c81fdee29600d66d9dcb1a4f109a78aeba51f6`.

La implementación está publicada para revisión; no se fusionó ni desplegó en
producción. La PWA de alumnos todavía usa Firebase y conserva su Cocina antigua;
el portal mantiene el adaptador REST legacy. Conectar las interfaces a estas
funciones nuevas, retirar esa Cocina y migrar Firestore son trabajos posteriores.
No se probaron certificados del dominio real, proveedores de correo/push reales
ni capacidad para miles de usuarios simultáneos.

Reglas, decisiones y migración:
[IMPLEMENTACION_V3_2.md](../backend/IMPLEMENTACION_V3_2.md).
Arranque: [DESPLIEGUE_CONTENEDOR_UNICO.md](../backend/DESPLIEGUE_CONTENEDOR_UNICO.md).
Los reportes anteriores son evidencia histórica de sus respectivos commits;
este informe documenta el código V3.2 indicado arriba.
