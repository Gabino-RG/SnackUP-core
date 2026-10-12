# Validación del módulo administrativo

Fecha de revisión: 4 de octubre de 2026 (México). Rama: `test/api-aaa-sonarqube`. Base anterior: `3697f5f3b5b5ff152c94b5be26ba340559e9ce3a`.

La verificación posterior de la aplicación completa está en [VALIDACION_INTEGRADA.md](../VALIDACION_INTEGRADA.md). Este documento conserva los resultados de la primera entrega administrativa.

## Resultados ejecutados

| Comprobación | Resultado |
|---|---|
| Flutter 3.32.0 / Dart 3.8.0, `flutter test --no-pub` | **26 pruebas aprobadas**: 14 de administración, 8 de reseñas y 4 existentes. |
| Análisis de `lib/features/admin` con infos fatales | Sin incidencias. |
| Análisis global con la misma tolerancia de CI | Sin errores; persisten 204 avisos heredados (incluidas 4 advertencias). Los archivos nuevos de administración no añaden incidencias. |
| Compilación web de `lib/main_admin_demo.dart` | Correcta, con CanvasKit local. |
| Compilación web de la app completa, `lib/main.dart` | Correcta. No implica validación funcional de producción. |
| Navegador Chromium 134, escritorio 1440×1100 y móvil 390×844 | Demo renderizada; navegación a locales, seguimiento y detalle comprobada. Sin errores JavaScript ni solicitudes externas durante el recorrido final. |
| JavaScript del generador Figma y suite candidata de reglas | `node --check` correcto. |
| Cambios de texto | `git diff --check` correcto. |

## Casos cubiertos

Promedio global ponderado por reseña; exclusión de dimensiones históricas ausentes; valores inválidos; combinación de filtros; límites de fechas y horario UTC−6; orden cronológico; historial de seguimiento; desktop y móvil poblado/vacío; carga parcial; fallo de carga sin datos ficticios de sustitución; apertura y guardado del seguimiento; normalización académica; tres escalas 1–5; límites de texto; ausencia de nombre/correo/matrícula en payload nuevo; pedido propio, completado y del local correcto.

La revisión estática detectó y corrigió una vía de lectura de reseñas históricas mediante un ID de pedido coincidente. La candidata ahora permite la lectura del espacio vacío del pedido solamente cuando la reseña todavía no existe. También se corrigieron cursores que podían avanzar antes de una conversión fallida, filtros que perdían su etiqueta y desbordamientos de la interfaz.

## Evidencias visuales

Las cifras y los locales de estas capturas son demostración, no valoraciones reales de negocios del campus.

- [Panorama de escritorio](./capturas/01_resumen_escritorio.png)
- [Vista móvil](./capturas/02_resumen_movil.png)
- [Comparación de locales](./capturas/03_comparacion_locales.png)
- [Seguimiento](./capturas/04_seguimiento.png)
- [Detalle de opinión](./capturas/05_detalle_opinion.png)
- [Gráficas y segmentación](./capturas/06_graficas.png)

## Pendiente de validación externa

- Reglas Firestore: la suite `tests/api/admin-monitoring.test.mjs` quedó preparada y revisada en sintaxis; **no se ejecutó contra un emulador**. No se reintentó la ejecución anteriormente bloqueada por revisión automática de permisos.
- No se desplegaron reglas, otorgaron claims ni consultaron/escribieron datos reales de alumnos. El flujo con cuentas reales requiere un entorno aprobado y las reglas activadas.
- Figma: el archivo alternativo permanece parcial por la cuota del servicio. El generador de `design/figma-admin/` tiene sintaxis válida, pero no se ejecutó ni se validó visualmente dentro de Figma.
- Las pruebas de Flutter no acreditan carga de 2,000/2,500 usuarios, exactitud del padrón escolar, pagos ni otras áreas fuera del alcance del módulo.
