/* global figma */
// SnackUP — native Figma development plugin. No network calls or remote assets.
// Data is intentionally the same fictitious seed as the admin module.
'use strict';

async function main() {
  const created = [];
  const keep = node => { created.push(node.id); return node; };
  const FONT = 'Inter';
  const PAGE = 'Administración · Entrega';
  const palette = {
    navy: '#002654', lime: '#C4D600', cyan: '#008BBE', bg: '#F8F9FA',
    white: '#FFFFFF', ink: '#152B43', muted: '#687888', border: '#E3E9EE',
    blueLight: '#EAF4FA', limeLight: '#F3F7D5', red: '#B43F43',
    redLight: '#FFF0EF', green: '#227D68', greenLight: '#EAF6F1',
    amber: '#9B6308', amberLight: '#FFF5E2',
  };
  const stores = [
    { name: 'Cafetería Central', rating: '3.8', service: '3.9', food: '3.8', negatives: 4, state: 'Estable', stars: '★★★★☆' },
    { name: 'La Terraza', rating: '2.3', service: '2.0', food: '2.4', negatives: 16, state: 'Revisar', stars: '★★☆☆☆' },
    { name: 'Rincón del Café', rating: '4.7', service: '4.7', food: '5.0', negatives: 0, state: 'Estable', stars: '★★★★★' },
    { name: 'Snack & Go', rating: '3.8', service: '3.8', food: '3.8', negatives: 4, state: 'Estable', stars: '★★★★☆' },
  ];
  const types = {
    display: [32, 'Bold', 40], title: [24, 'Bold', 32], heading: [18, 'Semi Bold', 26],
    body: [14, 'Regular', 22], label: [14, 'Semi Bold', 20], caption: [12, 'Medium', 18],
    tiny: [11, 'Medium', 16], metric: [32, 'Bold', 40],
  };
  const fonts = await figma.listAvailableFontsAsync();
  for (const style of ['Regular', 'Medium', 'Semi Bold', 'Bold']) {
    if (!fonts.some(f => f.fontName.family === FONT && f.fontName.style === style)) {
      throw new Error(`Falta la fuente ${FONT} ${style}. Instálala antes de ejecutar.`);
    }
  }
  await Promise.all(['Regular', 'Medium', 'Semi Bold', 'Bold'].map(style => figma.loadFontAsync({ family: FONT, style })));

  let pageName = PAGE;
  let suffix = 2;
  while (figma.root.children.some(p => p.name === pageName)) pageName = `${PAGE} (${suffix++})`;
  const page = keep(figma.createPage());
  page.name = pageName;
  await figma.setCurrentPageAsync(page);

  // Local primitives and semantic aliases are created before any component.
  const collection = figma.variables.createVariableCollection(`SnackUP · ${pageName}`);
  const mode = collection.modes[0].modeId;
  collection.renameMode(mode, 'Light');
  const tokens = {};
  function rgb(hex) {
    return { r: parseInt(hex.slice(1, 3), 16) / 255, g: parseInt(hex.slice(3, 5), 16) / 255, b: parseInt(hex.slice(5, 7), 16) / 255 };
  }
  function variable(name, type, value, scopes) {
    const v = figma.variables.createVariable(name, collection, type);
    v.setValueForMode(mode, value);
    v.scopes = scopes;
    v.setVariableCodeSyntax('WEB', `var(--snackup-${name.replace(/\//g, '-')})`);
    tokens[name] = v;
    return v;
  }
  for (const [name, hex] of Object.entries(palette)) {
    const primitive = variable(`primitive/${name}`, 'COLOR', rgb(hex), []);
    variable(`color/${name}`, 'COLOR', { type: 'VARIABLE_ALIAS', id: primitive.id }, ['FRAME_FILL', 'SHAPE_FILL', 'TEXT_FILL', 'STROKE_COLOR']);
  }
  for (const value of [4, 8, 12, 16, 20, 24, 32, 40]) variable(`space/${value}`, 'FLOAT', value, ['GAP']);
  for (const value of [8, 12, 16, 20, 999]) variable(`radius/${value}`, 'FLOAT', value, ['CORNER_RADIUS']);
  const textStyles = {};
  for (const [name, [size, style, line]] of Object.entries(types)) {
    const s = figma.createTextStyle();
    s.name = `SnackUP / ${pageName} / ${name}`;
    s.fontName = { family: FONT, style };
    s.fontSize = size;
    s.lineHeight = { unit: 'PIXELS', value: line };
    textStyles[name] = s;
  }

  function paint(name) {
    return figma.variables.setBoundVariableForPaint({ type: 'SOLID', color: rgb(palette[name]) }, 'color', tokens[`color/${name}`]);
  }
  function fill(node, name) { node.fills = name ? [paint(name)] : []; }
  function boundSpace(node, prop, value) {
    if (tokens[`space/${value}`]) node.setBoundVariable(prop, tokens[`space/${value}`]);
    else node[prop] = value;
  }
  function radius(node, value = 16) { node.setBoundVariable('cornerRadius', tokens[`radius/${value}`]); }
  function border(node, name = 'border') { node.strokes = [paint(name)]; node.strokeWeight = 1; }
  function configure(node, name, width, direction, gap, padding, background) {
    node.name = name;
    node.resize(width || 10, 10);
    node.layoutMode = direction;
    node.primaryAxisSizingMode = direction === 'HORIZONTAL' && width ? 'FIXED' : 'AUTO';
    node.counterAxisSizingMode = direction === 'VERTICAL' && width ? 'FIXED' : 'AUTO';
    boundSpace(node, 'itemSpacing', gap);
    for (const side of ['paddingTop', 'paddingBottom', 'paddingLeft', 'paddingRight']) boundSpace(node, side, padding);
    fill(node, background);
    node.clipsContent = false;
    return node;
  }
  function box(parent, name, width, direction = 'VERTICAL', gap = 8, padding = 0, background = null) {
    const n = configure(keep(figma.createFrame()), name, width, direction, gap, padding, background);
    if (parent) parent.appendChild(n);
    return n;
  }
  async function text(parent, name, content, role = 'body', color = 'ink', width = null) {
    const n = keep(figma.createText());
    n.name = name;
    n.fontName = { family: FONT, style: types[role][1] };
    await n.setTextStyleIdAsync(textStyles[role].id);
    n.characters = content;
    fill(n, color);
    if (width !== null) { n.resize(width, 10); n.textAutoResize = 'HEIGHT'; }
    else n.textAutoResize = 'WIDTH_AND_HEIGHT';
    parent.appendChild(n);
    return n;
  }
  function rect(parent, name, width, height, color, round = 0) {
    const n = keep(figma.createRectangle());
    n.name = name;
    n.resize(Math.max(0.1, width), height);
    fill(n, color);
    if (round) radius(n, round);
    parent.appendChild(n);
    return n;
  }
  async function tag(parent, label, kind = 'blue') {
    const colors = { blue: ['blueLight', 'navy'], red: ['redLight', 'red'], green: ['greenLight', 'green'], lime: ['limeLight', 'navy'] };
    const n = box(parent, `Estado / ${label}`, null, 'HORIZONTAL', 4, 0, colors[kind][0]);
    for (const side of ['paddingLeft', 'paddingRight']) boundSpace(n, side, 12);
    for (const side of ['paddingTop', 'paddingBottom']) boundSpace(n, side, 4);
    radius(n, 999);
    await text(n, 'Etiqueta', label, 'tiny', colors[kind][1]);
    return n;
  }
  async function sectionTitle(parent, title, subtitle, width) {
    const n = box(parent, `Título / ${title}`, width, 'VERTICAL', 4);
    await text(n, 'Título', title, 'heading', 'navy', width);
    if (subtitle) await text(n, 'Descripción', subtitle, 'caption', 'muted', width);
    return n;
  }
  function card(parent, name, width, gap = 16, padding = 24) {
    const n = box(parent, name, width, 'VERTICAL', gap, padding, 'white');
    border(n); radius(n);
    return n;
  }

  // Small component family: label fields are exposed as native text properties.
  const masterArea = box(page, 'Componentes reutilizables · SnackUP', 500, 'VERTICAL', 24, 24, 'bg');
  masterArea.x = 3900; masterArea.y = 160;
  await text(masterArea, 'Título', 'SnackUP / Componentes', 'title', 'navy');
  const properties = new Map();
  function component(name, width, gap, padding) {
    const n = configure(keep(figma.createComponent()), `SnackUP / ${name}`, width, 'VERTICAL', gap, padding, 'white');
    n.description = `Componente editable del módulo administrativo SnackUP: ${name}. Datos de demostración.`;
    border(n); radius(n);
    masterArea.appendChild(n);
    properties.set(n.id, {});
    return n;
  }
  async function field(comp, parent, name, value, role = 'label', color = 'ink', width = null) {
    const n = await text(parent, name, value, role, color, width);
    const key = comp.addComponentProperty(name, 'TEXT', value);
    n.componentPropertyReferences = { characters: key };
    properties.get(comp.id)[name] = key;
    return n;
  }
  function instance(parent, comp, values, width = null) {
    const n = keep(comp.createInstance());
    parent.appendChild(n);
    const props = {};
    for (const [name, value] of Object.entries(values)) props[properties.get(comp.id)[name]] = value;
    n.setProperties(props);
    if (width !== null) {
      n.resize(width, n.height);
      n.primaryAxisSizingMode = 'AUTO';
      n.counterAxisSizingMode = 'FIXED';
    }
    return n;
  }

  const filterMaster = component('Filtro', 220, 4, 12);
  await field(filterMaster, filterMaster, 'Etiqueta', 'Carrera', 'tiny', 'muted');
  await field(filterMaster, filterMaster, 'Valor', 'Todas las carreras  ⌄', 'label', 'navy');
  const metricMaster = component('Indicador', 278, 8, 20);
  await field(metricMaster, metricMaster, 'Etiqueta', 'Valoración global', 'caption', 'muted');
  await field(metricMaster, metricMaster, 'Valor', '3.7 / 5', 'metric', 'navy');
  await field(metricMaster, metricMaster, 'Contexto', '96 opiniones en el periodo', 'tiny', 'muted', 238);
  const storeMaster = component('Local', 278, 12, 20);
  await field(storeMaster, storeMaster, 'Nombre', 'Cafetería Central', 'heading', 'navy', 238);
  const sr = box(storeMaster, 'Puntaje', 238, 'HORIZONTAL', 8); sr.counterAxisAlignItems = 'CENTER';
  await field(storeMaster, sr, 'Puntaje', '3.8', 'metric', 'navy');
  await field(storeMaster, sr, 'Estrellas', '★★★★☆', 'label', 'amber');
  await text(sr, 'Escala', '/ 5', 'caption', 'muted');
  await field(storeMaster, storeMaster, 'Muestra', '24 evaluaciones', 'caption', 'muted');
  rect(storeMaster, 'Separador', 238, 1, 'border');
  for (const [name, label, value] of [['Servicio', 'Servicio', '3.9 / 5'], ['Alimentos', 'Calidad de alimentos', '3.8 / 5']]) {
    const r = box(storeMaster, label, 238, 'HORIZONTAL', 8); r.primaryAxisAlignItems = 'SPACE_BETWEEN';
    await text(r, 'Etiqueta', label, 'caption', 'muted');
    await field(storeMaster, r, name, value, 'label', 'navy');
  }
  await field(storeMaster, storeMaster, 'Estado', '4 opiniones de 1–2 ★ · Estable', 'tiny', 'muted', 238);
  const buttonMaster = component('Botón', null, 8, 12);
  buttonMaster.layoutMode = 'HORIZONTAL';
  buttonMaster.primaryAxisSizingMode = 'AUTO'; buttonMaster.counterAxisSizingMode = 'AUTO';
  buttonMaster.strokes = []; fill(buttonMaster, 'navy'); radius(buttonMaster, 8);
  boundSpace(buttonMaster, 'paddingLeft', 16); boundSpace(buttonMaster, 'paddingRight', 16);
  await field(buttonMaster, buttonMaster, 'Etiqueta', 'Revisar opiniones', 'label', 'white');
  function button(parent, label, style = 'primary') {
    const n = instance(parent, buttonMaster, { Etiqueta: label });
    if (style !== 'primary') {
      fill(n, style === 'lime' ? 'lime' : 'white');
      for (const t of n.findAllWithCriteria({ types: ['TEXT'] })) fill(t, 'navy');
      if (style === 'outline') border(n);
    }
    return n;
  }
  function filter(parent, label, value, width = 220) { return instance(parent, filterMaster, { Etiqueta: label, Valor: `${value}  ⌄` }, width); }
  function metric(parent, label, value, description, width = null) { return instance(parent, metricMaster, { Etiqueta: label, Valor: value, Contexto: description }, width); }
  function storeCard(parent, data, width = null) {
    const n = instance(parent, storeMaster, { Nombre: data.name, Puntaje: data.rating, Estrellas: data.stars, Muestra: '24 evaluaciones', Servicio: `${data.service} / 5`, Alimentos: `${data.food} / 5`, Estado: `${data.negatives} opiniones de 1–2 ★ · ${data.state}` }, width);
    if (data.state === 'Revisar') {
      border(n, 'red');
      for (const t of n.findAllWithCriteria({ types: ['TEXT'] })) if (t.name === 'Estado') fill(t, 'red');
    }
    return n;
  }

  const iconPaths = {
    grid: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
    shop: '<path d="M3 9l2-6h14l2 6M3 9h18M5 9v11h14V9M9 20v-6h6v6"/>',
    chat: '<path d="M21 12a9 9 0 0 1-9 9 9 9 0 0 1-4-1l-5 1 1-5a9 9 0 1 1 17-4zM8 9h8M8 13h5"/>',
    check: '<rect x="4" y="3" width="16" height="18" rx="3"/><path d="M8 11l3 3 5-6"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  };
  function icon(parent, name, color) {
    const n = keep(figma.createNodeFromSvg(`<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="${palette[color]}" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${iconPaths[name]}</svg>`));
    n.name = `Icono / ${name}`; parent.appendChild(n); return n;
  }
  async function shell(name, x, active) {
    const root = box(page, name, 1440, 'HORIZONTAL', 0, 0, 'bg'); root.x = x; root.y = 160;
    const side = box(root, 'Navegación lateral', 216, 'VERTICAL', 8, 20, 'navy');
    side.layoutAlign = 'STRETCH';
    const identity = box(side, 'Identidad', 176, 'HORIZONTAL', 0);
    await text(identity, 'Snack', 'Snack', 'title', 'white'); await text(identity, 'UP', 'UP', 'title', 'lime');
    await text(side, 'Campus', 'UT SAN JUAN DEL RÍO', 'tiny', 'white');
    rect(side, 'Separación', 176, 32, 'navy');
    await text(side, 'Menú', 'SUPERVISIÓN', 'tiny', 'white');
    const nav = {};
    for (const [label, symbol] of [['Panorama general', 'grid'], ['Locales', 'shop'], ['Opiniones', 'chat'], ['Seguimiento', 'check'], ['Plan y avances', 'clock']]) {
      const selected = label === active;
      const row = box(side, label, 176, 'HORIZONTAL', 12, 12, selected ? 'lime' : 'navy');
      row.counterAxisAlignItems = 'CENTER'; radius(row, 12);
      icon(row, symbol, selected ? 'navy' : 'white');
      await text(row, 'Etiqueta', label, 'caption', selected ? 'navy' : 'white', 106);
      nav[label] = row;
    }
    rect(side, 'Separación', 176, 48, 'navy');
    await text(side, 'Acceso', 'Acceso administrativo', 'caption', 'white', 176);
    await text(side, 'Propósito', 'Información para mejorar el servicio del campus.', 'tiny', 'white', 176);
    const mainPanel = box(root, 'Contenido', 1224, 'VERTICAL', 0);
    const top = box(mainPanel, 'Barra superior', 1224, 'HORIZONTAL', 16, 0, 'white');
    top.resize(1224, 72); top.counterAxisSizingMode = 'FIXED'; top.counterAxisAlignItems = 'CENTER';
    top.primaryAxisAlignItems = 'SPACE_BETWEEN';
    boundSpace(top, 'paddingLeft', 32); boundSpace(top, 'paddingRight', 32);
    await text(top, 'Ruta', 'Cafeterías del campus  /  Administración', 'caption', 'muted');
    await tag(top, 'Vista administrativa');
    const body = box(mainPanel, 'Panel principal', 1224, 'VERTICAL', 24, 32);
    return { root, body, nav };
  }
  async function demo(parent, width = 1160) {
    const n = box(parent, 'Datos de demostración', width, 'HORIZONTAL', 12, 12, 'limeLight'); radius(n, 8);
    await text(n, 'Etiqueta', 'DEMO', 'tiny', 'navy');
    await text(n, 'Aviso', 'Locales y opiniones ficticios para validar el módulo. No representan evaluaciones reales.', 'caption', 'navy', width - 92);
  }
  async function ratingBar(parent, label, value, width = 566, color = 'navy') {
    const row = box(parent, `Barra / ${label}`, width, 'HORIZONTAL', 12); row.counterAxisAlignItems = 'CENTER';
    await text(row, 'Etiqueta', label, 'caption', 'muted', 86);
    const trackWidth = width - 142;
    const track = box(row, 'Escala 0–5', trackWidth, 'HORIZONTAL', 0, 0, 'bg');
    track.resize(trackWidth, 10); track.counterAxisSizingMode = 'FIXED'; radius(track, 8);
    rect(track, 'Valor editable', trackWidth * value / 5, 10, color, 8);
    await text(row, 'Valor', value.toFixed(1), 'label', 'navy', 32);
  }
  async function comments(parent, width, compact = false) {
    const rows = [
      ['Administración · AD01SV-26', '11:01 h · 1 ★', '“Esperé demasiado y no me avisaron del retraso.”', 'Por revisar'],
      ['Mecatrónica · ME03SM-26', '11:05 h · 2 ★', '“Esperé demasiado y no me avisaron del retraso.”', 'En revisión'],
      ['Química · QI02SM-26', '11:09 h · 2 ★', '“Esperé demasiado y no me avisaron del retraso.”', 'Por revisar'],
    ];
    for (const [group, when, quote, status] of rows.slice(0, compact ? 1 : 3)) {
      const item = box(parent, 'Opinión de ejemplo', width, 'VERTICAL', 8, 16, 'bg'); radius(item, 12);
      const header = box(item, 'Perfil académico y estado', width - 32, compact ? 'VERTICAL' : 'HORIZONTAL', 8);
      header.primaryAxisAlignItems = compact ? 'MIN' : 'SPACE_BETWEEN';
      await text(header, 'Carrera y grupo', group, 'caption', 'navy', compact ? width - 32 : width - 164);
      await tag(header, status, 'red');
      await text(item, 'Fecha y estrellas', when, 'tiny', 'muted');
      await text(item, 'Comentario', quote, 'body', 'ink', width - 32);
    }
  }

  const overview = await shell('01 · Panorama administrativo', 160, 'Panorama general');
  const h = box(overview.body, 'Cabecera', 1160, 'HORIZONTAL', 16); h.primaryAxisAlignItems = 'SPACE_BETWEEN'; h.counterAxisAlignItems = 'CENTER';
  const ht = box(h, 'Títulos', 860, 'VERTICAL', 8);
  await text(ht, 'Antetítulo', 'ESCUCHAR. MEDIR. MEJORAR.', 'tiny', 'cyan');
  await text(ht, 'Título', 'Así se vive el servicio en tu campus', 'display', 'navy', 860);
  await text(ht, 'Descripción', 'Las opiniones de los alumnos, convertidas en acciones para los cuatro locales.', 'body', 'muted', 860);
  button(h, 'Exportar resumen');
  await demo(overview.body);
  const filters = box(overview.body, 'Filtros', 1160, 'HORIZONTAL', 12);
  // 200 + 188 + 244 + 244 + 236 + four 12 px gaps = 1160.
  for (const [label, value, width] of [['Periodo', 'Últimos 30 días', 200], ['Local', 'Los 4 locales', 188], ['Carrera', 'Todas las carreras', 244], ['Grupo', 'Todos los grupos', 244], ['Horario', 'Todos', 236]]) filter(filters, label, value, width);
  const kpis = box(overview.body, 'Indicadores', 1160, 'HORIZONTAL', 16);
  metric(kpis, 'Valoración global', '3.7 / 5', '96 evaluaciones en el periodo');
  metric(kpis, 'Participación', '96', '24 opiniones por cada local');
  metric(kpis, 'Opiniones de 1–2 ★', '25 %', '24 opiniones requieren escucha');
  metric(kpis, 'Locales con alerta', '1 de 4', 'La Terraza · revisar tiempos');
  const storesSection = box(overview.body, 'Comparación de locales', 1160, 'VERTICAL', 12);
  await sectionTitle(storesSection, 'Un vistazo a cada local', 'Promedios de 1 a 5 estrellas · muestra visible por local', 1160);
  const storeRow = box(storesSection, 'Cuatro locales', 1160, 'HORIZONTAL', 16);
  const shopInstances = stores.map(data => storeCard(storeRow, data));
  const chartRow = box(overview.body, 'Gráficas', 1160, 'HORIZONTAL', 16);
  const comparison = card(chartRow, 'Servicio y alimentos', 706);
  await sectionTitle(comparison, '¿Dónde está la diferencia?', 'Servicio y calidad de alimentos por local', 658);
  const legend = box(comparison, 'Leyenda', 658, 'HORIZONTAL', 16);
  for (const [label, color] of [['Servicio', 'navy'], ['Alimentos', 'cyan']]) {
    const l = box(legend, label, null, 'HORIZONTAL', 8); l.counterAxisAlignItems = 'CENTER';
    rect(l, 'Color', 10, 10, color, 8); await text(l, 'Etiqueta', label, 'caption', 'muted');
  }
  for (const data of stores) {
    const row = box(comparison, data.name, 658, 'VERTICAL', 8);
    await text(row, 'Local', data.name, 'label', 'navy');
    const bars = box(row, 'Series', 658, 'VERTICAL', 8);
    await ratingBar(bars, 'Servicio', Number(data.service), 658, 'navy');
    await ratingBar(bars, 'Alimentos', Number(data.food), 658, 'cyan');
  }
  await text(comparison, 'Nota', 'Escala fija: 0–5. Servicio y alimentos omiten respuestas sin dimensión registrada.', 'tiny', 'muted', 658);
  const careers = card(chartRow, 'Participación por carrera', 438);
  await sectionTitle(careers, '¿Quiénes están opinando?', 'Participación por carrera · 96 opiniones', 390);
  for (const [name, count, color] of [['Tecnologías de la Información', 20, 'navy'], ['Administración', 20, 'cyan'], ['Mecatrónica', 24, 'lime'], ['Química', 24, 'green'], ['Sin informar', 8, 'muted']]) {
    const r = box(careers, name, 390, 'VERTICAL', 8);
    const row = box(r, 'Etiqueta y cantidad', 390, 'HORIZONTAL', 8); row.primaryAxisAlignItems = 'SPACE_BETWEEN';
    await text(row, 'Carrera', name, 'caption', 'ink'); await text(row, 'Cantidad', String(count), 'label', 'navy');
    const track = box(r, 'Escala 0–24', 390, 'HORIZONTAL', 0, 0, 'bg'); track.resize(390, 10); track.counterAxisSizingMode = 'FIXED'; radius(track, 8);
    rect(track, 'Opiniones', 390 * count / 24, 10, color, 8);
  }
  await text(careers, 'Nota', 'Los datos sin carrera se conservan como “Sin informar”. Cada opinión cuenta una vez.', 'tiny', 'muted', 390);
  const attention = box(overview.body, 'Alerta prioritaria', 1160, 'HORIZONTAL', 20, 20, 'redLight'); radius(attention, 12);
  const attentionText = box(attention, 'Motivo', 900, 'VERTICAL', 4);
  await text(attentionText, 'Título', 'La Terraza necesita una revisión', 'label', 'red');
  await text(attentionText, 'Descripción', '16 de 24 opiniones tienen 1–2 estrellas. Revisa los comentarios, acuerda mejoras y registra su seguimiento.', 'body', 'ink', 900);
  const reviewButton = button(attention, 'Revisar opiniones');
  const voice = card(overview.body, 'La voz de los alumnos', 1160);
  await sectionTitle(voice, 'La voz de los alumnos', 'Opiniones de ejemplo · sin nombres ni números de control visibles', 1112);
  await comments(voice, 1112, true);
  await text(overview.body, 'Pie', 'SnackUP · Supervisión institucional / Modo demostración', 'tiny', 'muted');

  const detail = await shell('02 · La Terraza · Opiniones y seguimiento', 1800, 'Opiniones');
  const backButton = button(detail.body, '←  Volver al panorama', 'outline');
  const detailTitle = box(detail.body, 'Cabecera', 1160, 'HORIZONTAL', 16); detailTitle.primaryAxisAlignItems = 'SPACE_BETWEEN';
  const detailText = box(detailTitle, 'Títulos', 840, 'VERTICAL', 8);
  await text(detailText, 'Antetítulo', 'LOCAL 02 / SUPERVISIÓN', 'tiny', 'cyan');
  await text(detailText, 'Título', 'La Terraza', 'display', 'navy');
  await text(detailText, 'Descripción', 'Escuchar los comentarios es el primer paso para mejorar el servicio.', 'body', 'muted', 840);
  await tag(detailTitle, 'Revisión prioritaria', 'red');
  await demo(detail.body);
  const detailFilters = box(detail.body, 'Segmentar opiniones', 1160, 'HORIZONTAL', 12);
  for (const [label, value] of [['Carrera', 'Todas las carreras'], ['Grupo', 'Todos los grupos'], ['Horario', 'Todos'], ['Valoración', '1–5 estrellas'], ['Estado', 'Todos']]) filter(detailFilters, label, value, 222.4);
  const detailKpis = box(detail.body, 'Indicadores del local', 1160, 'HORIZONTAL', 16);
  metric(detailKpis, 'Valoración general', '2.3 / 5', '24 evaluaciones');
  metric(detailKpis, 'Servicio', '2.0 / 5', 'Dimensión de atención al alumno');
  metric(detailKpis, 'Calidad de alimentos', '2.4 / 5', 'Dimensión de alimentos');
  metric(detailKpis, 'Opiniones de 1–2 ★', '66.7 %', '16 de 24 opiniones');
  const middle = box(detail.body, 'Distribución y seguimiento', 1160, 'HORIZONTAL', 16);
  const distribution = card(middle, 'Distribución de estrellas', 438);
  await sectionTitle(distribution, 'Cómo se distribuyen las estrellas', '24 opiniones · todas las valoraciones cuentan', 390);
  for (const [stars, count] of [[5, 0], [4, 4], [3, 4], [2, 12], [1, 4]]) {
    const row = box(distribution, `${stars} estrellas`, 390, 'HORIZONTAL', 12); row.counterAxisAlignItems = 'CENTER';
    await text(row, 'Estrellas', `${stars} ★`, 'label', 'amber', 38);
    const track = box(row, 'Escala 0–24', 290, 'HORIZONTAL', 0, 0, 'bg'); track.resize(290, 14); track.counterAxisSizingMode = 'FIXED'; radius(track, 8);
    if (count) rect(track, 'Cantidad', 290 * count / 24, 14, stars <= 2 ? 'red' : 'cyan', 8);
    await text(row, 'Cantidad', String(count), 'label', 'navy', 38);
  }
  await text(distribution, 'Lectura', 'La mayoría de las opiniones se concentra en 2 estrellas. Revisa el contenido y el contexto antes de definir una acción.', 'body', 'muted', 390);
  const followup = card(middle, 'Seguimiento de mejora', 706);
  await sectionTitle(followup, 'De la opinión a la mejora', 'Registro de ejemplo · no se ha enviado una notificación al local', 658);
  const steps = box(followup, 'Etapas del seguimiento', 658, 'HORIZONTAL', 12);
  for (const [i, label] of ['Recibida', 'En revisión', 'Acuerdo', 'Verificación'].entries()) {
    const step = box(steps, label, 155.5, 'VERTICAL', 8, 12, i === 1 ? 'blueLight' : 'bg'); radius(step, 8);
    await text(step, 'Número', `0${i + 1}`, 'label', i === 1 ? 'cyan' : 'muted');
    await text(step, 'Nombre', label, 'caption', 'navy', 131.5);
  }
  filter(followup, 'Responsable', 'Administración del campus', 658);
  const note = box(followup, 'Nota de seguimiento', 658, 'VERTICAL', 8, 16, 'bg'); radius(note, 12);
  await text(note, 'Etiqueta', 'ACUERDO PROPUESTO', 'tiny', 'muted');
  await text(note, 'Contenido', 'Revisar tiempos de entrega y avisos de retraso con el encargado. Registrar el acuerdo y volver a evaluar en la siguiente semana.', 'body', 'ink', 626);
  const actions = box(followup, 'Acciones', 658, 'HORIZONTAL', 12);
  button(actions, 'Guardar seguimiento'); button(actions, 'Ver historial', 'outline');
  const opinions = card(detail.body, 'Opiniones segmentadas', 1160);
  await sectionTitle(opinions, 'Qué están diciendo los alumnos', 'Carrera, grupo y horario acompañan cada opinión para entender su contexto.', 1112);
  await comments(opinions, 1112);
  const projectPlan = card(detail.body, 'Línea del tiempo del proyecto', 1160);
  await sectionTitle(projectPlan, 'Línea del tiempo · siguiente etapa', 'Plan propuesto de 2026. Las fechas no prueban que las actividades se hayan realizado.', 1112);
  const planRow = box(projectPlan, 'Fases propuestas', 1112, 'HORIZONTAL', 12);
  for (const [period, title, desc] of [
    ['05–16 OCT', 'Módulo administrativo', 'Opiniones, filtros, gráficas y seguimiento.'],
    ['19–23 OCT', 'Revisión técnica', 'Arquitectura y permisos, sujetos a aprobación.'],
    ['26–30 OCT', 'Pruebas', 'Validación con alumnos y responsables.'],
    ['02–06 NOV', 'Piloto', 'Uso supervisado y capacitación.'],
    ['09–13 NOV', 'Implementación', 'Ajustes del piloto y despliegue aprobado.'],
  ]) {
    const step = box(planRow, title, 212.8, 'VERTICAL', 8, 16, 'bg'); radius(step, 12);
    await text(step, 'Periodo', period, 'tiny', 'cyan');
    await text(step, 'Título', title, 'label', 'navy', 180.8);
    await text(step, 'Detalle', desc, 'caption', 'muted', 180.8);
  }
  await text(detail.body, 'Pie', 'Datos de demostración · Historial y notas visibles solo para administración', 'tiny', 'muted');

  const mobile = box(page, '03 · Supervisión móvil', 390, 'VERTICAL', 0, 0, 'bg'); mobile.x = 3440; mobile.y = 160;
  const mobileTop = box(mobile, 'Cabecera móvil', 390, 'HORIZONTAL', 12, 20, 'navy'); mobileTop.primaryAxisAlignItems = 'SPACE_BETWEEN'; mobileTop.counterAxisAlignItems = 'CENTER';
  await text(mobileTop, 'Marca', 'SnackUP', 'title', 'white'); await text(mobileTop, 'Área', 'SUPERVISIÓN', 'tiny', 'lime');
  const mobileBody = box(mobile, 'Contenido móvil', 390, 'VERTICAL', 20, 20);
  await text(mobileBody, 'Título', 'Tu campus, en perspectiva', 'title', 'navy', 350);
  await text(mobileBody, 'Descripción', 'Escucha a los alumnos. Da seguimiento a cada mejora.', 'body', 'muted', 350);
  await demo(mobileBody, 350);
  filter(mobileBody, 'Periodo', 'Últimos 30 días', 350);
  const mobileKpi = card(mobileBody, 'Indicadores de bolsillo', 350, 12, 20);
  const mkRow = box(mobileKpi, 'Promedio y muestra', 310, 'HORIZONTAL', 24);
  const a = box(mkRow, 'Promedio', 145, 'VERTICAL', 4); await text(a, 'Valor', '3.7 / 5', 'metric', 'navy'); await text(a, 'Etiqueta', 'Valoración global', 'caption', 'muted');
  const b = box(mkRow, 'Muestra', 141, 'VERTICAL', 4); await text(b, 'Valor', '96', 'metric', 'navy'); await text(b, 'Etiqueta', 'Opiniones', 'caption', 'muted');
  await tag(mobileKpi, '1 local necesita revisión', 'red');
  await sectionTitle(mobileBody, 'Los cuatro locales', '24 evaluaciones por local', 350);
  const mobileStores = [];
  for (const data of stores) {
    const row = card(mobileBody, data.name, 350, 8, 16);
    const upper = box(row, 'Identidad', 318, 'HORIZONTAL', 8); upper.primaryAxisAlignItems = 'SPACE_BETWEEN';
    await text(upper, 'Nombre', data.name, 'label', 'navy', 210); await text(upper, 'Puntaje', `${data.rating} ★`, 'label', 'amber');
    await ratingBar(row, 'General', Number(data.rating), 318, data.state === 'Revisar' ? 'red' : 'cyan');
    await text(row, 'Dimensiones', `Servicio ${data.service}  ·  Alimentos ${data.food}`, 'caption', 'muted', 318);
    if (data.state === 'Revisar') await tag(row, '16 opiniones de 1–2 ★', 'red');
    mobileStores.push(row);
  }
  const mobileAttention = card(mobileBody, 'Prioridad de hoy', 350, 12, 16);
  await sectionTitle(mobileAttention, 'Una opinión para atender', 'La Terraza · ejemplo', 318);
  await comments(mobileAttention, 318, true);
  const mobileReview = button(mobileAttention, 'Abrir seguimiento');
  const bottomNav = box(mobile, 'Navegación móvil', 390, 'HORIZONTAL', 8, 12, 'white');
  for (const [label, symbol] of [['Resumen', 'grid'], ['Locales', 'shop'], ['Opiniones', 'chat'], ['Seguimiento', 'check']]) {
    const item = box(bottomNav, label, 85.5, 'VERTICAL', 4); item.counterAxisAlignItems = 'CENTER';
    icon(item, symbol, label === 'Resumen' ? 'cyan' : 'muted');
    await text(item, 'Etiqueta', label, 'tiny', label === 'Resumen' ? 'navy' : 'muted');
  }

  async function link(node, destination) {
    await node.setReactionsAsync([{ trigger: { type: 'ON_CLICK' }, actions: [{ type: 'NODE', destinationId: destination.id, navigation: 'NAVIGATE', transition: null, preserveScrollPosition: false }] }]);
  }
  for (const node of [shopInstances[1], reviewButton, overview.nav.Opiniones, overview.nav.Seguimiento, mobileStores[1], mobileReview]) await link(node, detail.root);
  await link(backButton, overview.root); await link(detail.nav['Panorama general'], overview.root);
  await link(overview.nav['Plan y avances'], detail.root);

  // Structural checks run when the plugin is actually executed; they are not a visual QA substitute.
  const screens = [overview.root, detail.root, mobile];
  const allText = screens.flatMap(n => n.findAllWithCriteria({ types: ['TEXT'] }));
  const wrongFonts = allText.filter(n => n.fontName === figma.mixed || n.fontName.family !== FONT);
  if (wrongFonts.length) throw new Error('Se detectaron textos con una fuente distinta de Inter.');
  const invalidBounds = screens.flatMap(n => n.findAll(node => 'width' in node && (node.width <= 0 || !Number.isFinite(node.width))));
  if (invalidBounds.length) throw new Error('Se detectaron capas con un ancho inválido.');
  page.selection = [overview.root];
  figma.viewport.scrollAndZoomIntoView([overview.root]);
  console.info('SnackUP native design created', {
    pageId: page.id, createdNodeIds: created, frameIds: screens.map(n => n.id),
    textCount: allText.length, instanceCount: screens.reduce((n, s) => n + s.findAllWithCriteria({ types: ['INSTANCE'] }).length, 0),
    collectionId: collection.id, visualReview: 'Pendiente: inspeccionar las tres vistas al 100 %',
  });
  figma.closePlugin('Se crearon 3 pantallas editables de SnackUP. Revisa el diseño al 100 %.');
}

main().catch(error => {
  console.error(error);
  figma.closePlugin(`SnackUP: ${error.message || error}. Las páginas anteriores permanecen intactas.`);
});
