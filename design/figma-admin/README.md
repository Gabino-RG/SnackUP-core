# SnackUP · Diseño administrativo editable

Generador de tres vistas mediante la API estándar de plugins de Figma. Produce textos, gráficos vectoriales, auto-layout, variables, estilos y componentes editables. No importa capturas de pantalla ni consulta Firebase.

## Estado de entrega

El archivo original compartido (`6dgCPPbuEizddNItssfYWt`) no permitió acceso de edición al conector. Se creó [SnackUP · Supervisión de cafeterías](https://www.figma.com/design/NB0QoBVD9RNeUqUHM4JofI), pero la cuota MCP del plan Starter se agotó antes de componer las pantallas. Ese archivo contiene **fundamentos y componentes parciales**, no el diseño terminado.

Este código es la ruta de continuación. **Se verificó su sintaxis con `node --check code.js`; no se ejecutó ni se validó visualmente en Figma.** La revisión visual sigue pendiente. El plugin funciona fuera de MCP y requiere acceso de edición al archivo en el que se ejecute.

## Ejecutar

1. En Figma de escritorio, crea un plugin de desarrollo desde **Plugins → Development → New plugin**. Elige Figma Design y una ejecución sin interfaz. Figma genera su propio `id` de plugin.
2. Conserva ese `id` asignado por Figma y úsalo para sustituir `REEMPLAZAR_CON_ID_GENERADO_POR_FIGMA` en este `manifest.json`. Es un marcador explícito: no es un identificador publicado.
3. Importa el `manifest.json` desde **Plugins → Development → Import plugin from manifest**. Alternativamente, copia `code.js` a la carpeta creada en el paso 1 y conserva los campos `api`, `main`, `editorType`, `documentAccess` y `networkAccess` de este manifest junto con tu `id` real.
4. Abre un archivo de diseño donde puedas editar y ejecuta **SnackUP · Administración editable**.
5. El plugin añade una página nueva `Administración · Entrega` con tres pantallas y los componentes fuera de las pantallas. No elimina ni cambia las páginas anteriores. Si ya existe esa página, añade un sufijo numérico para conservarla.
6. Revisa las tres pantallas al 100 %, los textos, el ancho de los filtros y los enlaces de prototipo. La tarjeta **La Terraza** y el botón **Revisar opiniones** abren el detalle; el detalle vuelve al panorama.

## Contenido

- Panorama de cuatro locales: valoración global, servicio, alimentos, muestra, comentarios negativos y participación por carrera.
- Detalle de La Terraza: distribución de estrellas, comentarios con carrera/grupo/horario, seguimiento con responsable y notas, y plan propuesto del módulo.
- Vista móvil de supervisión con cuatro locales, alertas y una opinión prioritaria.
- Referencia institucional: Inter; azul `#002654`, lima `#C4D600`, cian `#008BBE` y fondo `#F8F9FA`.

Las cifras corresponden a la semilla de demostración del módulo: 96 opiniones, 24 por local, media redondeada 3.7 y 24 opiniones de 1–2 estrellas (25 %). Los nombres de locales son ficticios. En este diseño las cifras son texto y barras editables; no son consultas en vivo. Los filtros y el seguimiento son representación visual; los enlaces entre pantallas sí se configuran como navegación de prototipo.

El plan de octubre y noviembre se presenta como **propuesto, pendiente de validación**, sin afirmar que las actividades se realizaron. Los datos académicos sin registrar se muestran como `Sin informar`.

## API y ejecución

No requiere npm, compilación, token, dominio remoto, captura HTML ni librerías Figma externas. Utiliza exclusivamente funciones estándar de Figma Plugin API. Los gráficos usan rectángulos, vectores y texto editables. No usa extensiones MCP como `createAutoLayout`, `node.set`, `node.query` o `node.screenshot`.

Referencias oficiales consultadas:

- [Manifest de plugins](https://developers.figma.com/docs/plugins/manifest/)
- [Crear un plugin de desarrollo](https://help.figma.com/hc/en-us/articles/360042786733-Create-a-classic-plugin-for-development)
- [Figma Plugin API](https://developers.figma.com/docs/plugins/api/)
