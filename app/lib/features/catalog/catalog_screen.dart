import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../catalog/catalog.dart';

const catalogNavy = Color(0xFF002654);
const catalogBackground = Color(0xFFF8F9FA);

String catalogMessage(Object error) => error is CatalogException
    ? error.message : 'No se pudo completar la operación. Inténtalo de nuevo.';

class ProductImage extends StatelessWidget {
  const ProductImage({super.key, this.url, this.bytes, this.size = 88});
  final String? url;
  final Uint8List? bytes;
  final double size;
  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: const Color(0xFFEAF0F5),
      alignment: Alignment.center,
      child: Icon(Icons.restaurant_outlined, color: catalogNavy, size: size / 3),
    );
    Widget image = placeholder;
    try {
      if (bytes != null) {
        image = Image.memory(bytes!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder);
      } else if (url?.startsWith('data:image/') ?? false) {
        image = Image.memory(base64Decode(url!.split(',').last),
          fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder);
      } else if (url != null && url!.isNotEmpty) {
        image = Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder);
      }
    } catch (_) { image = placeholder; }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(width: size, height: size, child: image),
    );
  }
}

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, required this.businessId, required this.repository});
  final String businessId;
  final CatalogRepository repository;
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  CatalogPage? _data;
  Object? _error;
  bool _loading = true;
  bool? _available;
  int _page = 1, _revision = 0;
  final _busy = <String>{};

  @override
  void initState() { super.initState(); _load(); }
  @override
  void didUpdateWidget(CatalogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId || oldWidget.repository != widget.repository) {
      _debounce?.cancel(); _search.clear(); _page = 1; _available = null; _load();
    }
  }
  @override
  void dispose() { _debounce?.cancel(); _search.dispose(); super.dispose(); }

  Future<void> _load() async {
    final revision = ++_revision;
    setState(() { _loading = true; _error = null; });
    try {
      final data = await widget.repository.list(widget.businessId,
        query: CatalogQuery(page: _page, search: _search.text, available: _available));
      if (!mounted || revision != _revision) return;
      setState(() { _data = data; _page = data.page; _loading = false; });
      if (data.items.isEmpty && _page > 1) {
        _page--; await _load();
      }
    } catch (error) {
      if (mounted && revision == _revision) setState(() { _error = error; _loading = false; });
    }
  }

  void _message(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _edit([CatalogProduct? product]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => CatalogEditorScreen(
        repository: widget.repository, businessId: widget.businessId, productId: product?.id),
    ));
    if (saved == true && mounted) {
      _message('Catálogo actualizado.');
      await _load();
    }
  }

  ProductDraft _copy(CatalogProduct product, {int? priceCents, bool? available}) {
    final d = product.draft;
    return ProductDraft(
      name: d.name, description: d.description, category: d.category,
      priceCents: priceCents ?? d.priceCents, stock: d.stock, imageUrl: d.imageUrl,
      isFeatured: d.isFeatured, isAvailable: available ?? d.isAvailable,
    );
  }

  Future<void> _change(CatalogProduct product, ProductDraft draft) async {
    if (_busy.contains(product.id)) return;
    setState(() => _busy.add(product.id));
    try {
      await widget.repository.save(widget.businessId, draft, original: product);
      _message('Producto actualizado.');
    } catch (error) {
      _message(catalogMessage(error));
    } finally {
      if (mounted) { setState(() => _busy.remove(product.id)); await _load(); }
    }
  }

  Future<void> _price(CatalogProduct product) async {
    final cents = await showDialog<int>(context: context,
      builder: (_) => _PriceDialog(product: product));
    if (cents != null && mounted) await _change(product, _copy(product, priceCents: cents));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: catalogBackground,
    appBar: AppBar(
      title: const Text('Mi catálogo'),
      actions: [IconButton(
        tooltip: 'Actualizar catálogo', onPressed: _loading ? null : _load,
        icon: const Icon(Icons.refresh),
      )],
    ),
    body: Column(children: [
      if (widget.repository.isLocal) Container(
        width: double.infinity, color: const Color(0xFFFFF4D6),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: const Text('DATOS DE EJEMPLO · Los cambios se guardan en este dispositivo.',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
      Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        Row(children: [
          Expanded(child: Text(
            _data == null ? 'Productos de tu local' : '${_data!.total} productos encontrados',
            style: const TextStyle(fontWeight: FontWeight.w600))),
          FilledButton.icon(
            key: const ValueKey('add-product'), onPressed: () => _edit(),
            icon: const Icon(Icons.add), label: const Text('Agregar'),
          ),
        ]),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('catalog-search'), controller: _search,
          decoration: const InputDecoration(
            labelText: 'Buscar por nombre o categoría', prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 400), () { _page = 1; _load(); });
          },
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          for (final entry in <bool?, String>{null: 'Todos', true: 'Disponibles', false: 'No disponibles'}.entries)
            ChoiceChip(
              label: Text(entry.value), selected: _available == entry.key,
              onSelected: (_) { setState(() { _available = entry.key; _page = 1; }); _load(); },
            ),
        ]),
      ])),
      Expanded(child: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
              mainAxisSize: MainAxisSize.min, children: [
                Text(catalogMessage(_error!), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: _load, child: const Text('Reintentar')),
              ])))
          : _data!.items.isEmpty
            ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text(
                'No hay productos para estos filtros. Puedes agregar uno o cambiar la búsqueda.',
                textAlign: TextAlign.center)))
            : LayoutBuilder(builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1150 ? 3 : constraints.maxWidth >= 730 ? 2 : 1;
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns, mainAxisExtent: 278, crossAxisSpacing: 14, mainAxisSpacing: 14),
                  itemCount: _data!.items.length,
                  itemBuilder: (context, index) => _card(_data!.items[index]),
                );
              })),
      if (!_loading && _error == null && _data != null) SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(tooltip: 'Página anterior', onPressed: _page > 1
              ? () { _page--; _load(); } : null, icon: const Icon(Icons.chevron_left)),
          Text('Página $_page de ${_data!.totalPages == 0 ? 1 : _data!.totalPages}'),
          IconButton(tooltip: 'Página siguiente', onPressed: _page < _data!.totalPages
              ? () { _page++; _load(); } : null, icon: const Icon(Icons.chevron_right)),
        ]),
      )),
    ]),
  );

  Widget _card(CatalogProduct product) {
    final draft = product.draft;
    final busy = _busy.contains(product.id);
    return Card(margin: EdgeInsets.zero, child: Padding(
      padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ProductImage(url: draft.imageUrl),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(draft.name, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            const SizedBox(height: 6),
            Text(draft.category, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(draft.stock == null ? 'Sin conteo de existencias' : 'Existencias: ${draft.stock}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          ])),
        ]),
        const SizedBox(height: 8),
        Text(draft.description.isEmpty ? 'Sin descripción' : draft.description,
          maxLines: 1, overflow: TextOverflow.ellipsis),
        Row(children: [
          Text('\$${(draft.priceCents / 100).toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 24, color: catalogNavy, fontWeight: FontWeight.w700)),
          IconButton(
            tooltip: 'Cambiar precio de ${draft.name}',
            onPressed: busy ? null : () => _price(product), icon: const Icon(Icons.edit_outlined, size: 19),
          ),
          const Spacer(),
          if (draft.isFeatured) const Icon(Icons.star, color: Color(0xFFAB7C00), semanticLabel: 'Destacado'),
        ]),
        const Spacer(),
        Row(children: [
          Expanded(child: Text(draft.isAvailable ? 'Disponible' : 'No disponible', style: const TextStyle(fontSize: 13))),
          Switch(
            value: draft.isAvailable,
            onChanged: busy || draft.stock == 0 ? null : (value) => _change(product, _copy(product, available: value)),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: busy ? null : () => _edit(product), child: const Text('Editar')),
        ]),
      ]),
    ));
  }
}

class CatalogEditorScreen extends StatefulWidget {
  const CatalogEditorScreen({super.key, required this.repository, required this.businessId, this.productId});
  final CatalogRepository repository;
  final String businessId;
  final String? productId;
  @override
  State<CatalogEditorScreen> createState() => _CatalogEditorScreenState();
}

class _CatalogEditorScreenState extends State<CatalogEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _description = TextEditingController(),
      _category = TextEditingController(), _price = TextEditingController(), _stock = TextEditingController();
  CatalogProduct? _original;
  String? _imageUrl, _fileName;
  Uint8List? _imageBytes;
  bool _loading = false, _saving = false, _dirty = false, _allowPop = false,
      _available = true, _featured = false, _trackStock = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _trackStock = !widget.repository.supportsOptionalStock;
    _stock.text = '0';
    if (widget.productId != null) _load();
  }
  @override
  void dispose() {
    for (final c in [_name, _description, _category, _price, _stock]) { c.dispose(); }
    super.dispose();
  }
  void _changed() { if (!_dirty) setState(() => _dirty = true); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final product = await widget.repository.get(widget.businessId, widget.productId!);
      if (!mounted) return;
      final d = product.draft;
      _name.text = d.name; _description.text = d.description; _category.text = d.category;
      _price.text = (d.priceCents / 100).toStringAsFixed(2); _stock.text = (d.stock ?? 0).toString();
      setState(() {
        _original = product; _imageUrl = d.imageUrl; _imageBytes = null;
        _trackStock = d.stock != null || !widget.repository.supportsOptionalStock;
        _available = d.isAvailable; _featured = d.isFeatured; _dirty = false;
      });
    } catch (error) { if (mounted) setState(() => _error = error); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: Text(title), content: Text(message), actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Volver')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
        ],
      )) ?? false;

  Future<void> _close({bool saved = false}) async {
    if (_saving) return;
    if (!saved && _dirty && !await _confirm(
        'Cambios sin guardar', '¿Quieres salir y descartar los cambios?', 'Descartar')) return;
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(saved);
    });
  }

  Future<void> _pickImage() async {
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1400, imageQuality: 85);
      if (image == null) return;
      final bytes = await image.readAsBytes();
      validateProductImage(bytes, image.name);
      if (mounted) setState(() { _imageBytes = bytes; _fileName = image.name; _dirty = true; _error = null; });
    } catch (error) { if (mounted) setState(() => _error = error); }
  }

  Future<void> _save() async {
    if (_saving || _loading || !_form.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      if (_imageBytes != null) {
        final url = await widget.repository.uploadImage(widget.businessId, _imageBytes!, _fileName!);
        _imageUrl = url; _imageBytes = null;
      }
      final stock = _trackStock ? int.parse(_stock.text.trim()) : null;
      final draft = ProductDraft(
        name: _name.text.trim(), description: _description.text.trim(), category: _category.text.trim(),
        priceCents: parsePriceCents(_price.text)!, stock: stock, imageUrl: _imageUrl,
        isAvailable: stock == 0 ? false : _available, isFeatured: _featured,
      );
      await widget.repository.save(widget.businessId, draft, original: _original);
      if (!mounted) return;
      setState(() { _saving = false; _dirty = false; });
      await _close(saved: true);
    } catch (error) {
      if (mounted) setState(() { _saving = false; _error = error; });
    }
  }

  Future<void> _delete() async {
    final product = _original;
    if (_saving || product == null || !await _confirm(
      'Eliminar producto', 'Se quitará del catálogo. Los pedidos anteriores conservarán su nombre y precio registrados.',
      'Eliminar')) return;
    if (!mounted) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.repository.delete(product);
      if (!mounted) return;
      setState(() { _saving = false; _dirty = false; });
      await _close(saved: true);
    } catch (error) {
      if (mounted) setState(() { _saving = false; _error = error; });
    }
  }

  Widget _field(String key, String label, TextEditingController controller, {
    int maxLength = 160, int lines = 1, bool isRequired = false, TextInputType? keyboard,
    String? Function(String?)? validator,
  }) => Padding(padding: const EdgeInsets.only(bottom: 18), child: TextFormField(
    key: ValueKey(key), controller: controller, enabled: !_saving,
    maxLines: lines, maxLength: maxLength, keyboardType: keyboard,
    onChanged: (_) => _changed(),
    decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), counterText: ''),
    validator: validator ?? (value) => isRequired && (value?.trim().isEmpty ?? true) ? 'Completa este campo.' : null,
  ));

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: _allowPop || (!_saving && !_dirty),
    onPopInvokedWithResult: (didPop, result) { if (!didPop) _close(); },
    child: Scaffold(
      backgroundColor: catalogBackground,
      appBar: AppBar(
        leading: IconButton(tooltip: 'Volver al catálogo', onPressed: _saving ? null : () => _close(), icon: const Icon(Icons.arrow_back)),
        title: Text(widget.productId == null ? 'Agregar producto' : 'Editar producto'),
      ),
      body: _loading ? const Center(child: CircularProgressIndicator())
        : widget.productId != null && _original == null
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(padding: const EdgeInsets.all(24), child: Text(catalogMessage(_error ?? const CatalogException('No se pudo cargar.')))),
              FilledButton(onPressed: _load, child: const Text('Reintentar')),
            ]))
          : Align(alignment: Alignment.topCenter, child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: Form(key: _form, child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                // Keep every field mounted so validation includes offscreen fields.
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.repository.isLocal) const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text('DATOS DE EJEMPLO · Guardado local', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Wrap(spacing: 18, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    ProductImage(url: _imageUrl, bytes: _imageBytes, size: 120),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      OutlinedButton.icon(onPressed: _saving ? null : _pickImage,
                        icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('Elegir imagen')),
                      if (_imageUrl != null || _imageBytes != null)
                        TextButton(onPressed: _saving ? null : () => setState(() {
                          _imageUrl = null; _imageBytes = null; _dirty = true;
                        }), child: const Text('Quitar imagen')),
                      const Text('JPG, PNG o WebP · Hasta 5 MB', style: TextStyle(fontSize: 12)),
                    ]),
                  ]),
                  const SizedBox(height: 24),
                  _field('product-name', 'Nombre del producto', _name, isRequired: true),
                  _field('product-description', 'Descripción', _description, maxLength: 2000, lines: 3),
                  _field('product-category', 'Categoría', _category, maxLength: 120, isRequired: true),
                  _field('product-price', 'Precio (MXN)', _price, maxLength: 12,
                    keyboard: const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) => parsePriceCents(value ?? '') == null
                      ? 'Usa un precio de \$0.01 a \$10,000 con hasta 2 decimales.' : null),
                  if (_original != null) const Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: Text('Los cambios de precio se aplican a pedidos futuros.'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero, title: const Text('Controlar existencias'),
                    subtitle: Text(widget.repository.supportsOptionalStock
                      ? 'Desactívalo para productos que no se cuentan por unidad.'
                      : 'La conexión anterior requiere una cantidad de existencias.'),
                    value: _trackStock,
                    onChanged: _saving || !widget.repository.supportsOptionalStock ? null : (v) => setState(() {
                      _trackStock = v; _dirty = true;
                    }),
                  ),
                  if (_trackStock) _field('product-stock', 'Existencias', _stock, maxLength: 7,
                    keyboard: TextInputType.number,
                    validator: (value) {
                      final n = int.tryParse(value?.trim() ?? '');
                      return n == null || n < 0 || n > 1000000 ? 'Escribe un entero de 0 a 1,000,000.' : null;
                    }),
                  SwitchListTile(contentPadding: EdgeInsets.zero,
                    title: const Text('Disponible para pedidos'),
                    subtitle: const Text('Con cero existencias, se guardará como no disponible.'),
                    value: _available, onChanged: _saving ? null : (v) => setState(() { _available = v; _dirty = true; })),
                  SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Producto destacado'),
                    value: _featured, onChanged: _saving ? null : (v) => setState(() { _featured = v; _dirty = true; })),
                  if (_error != null) Container(
                    margin: const EdgeInsets.symmetric(vertical: 16), padding: const EdgeInsets.all(16),
                    color: const Color(0xFFFFEDEC),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(catalogMessage(_error!)),
                      if (_error is CatalogException && (_error as CatalogException).code == 'VERSION_CONFLICT')
                        TextButton(onPressed: _saving ? null : () async {
                          if (await _confirm('Recargar producto', 'Esto descartará los cambios del formulario.', 'Recargar')) _load();
                        }, child: const Text('Recargar producto')),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    key: const ValueKey('save-product'), onPressed: _saving ? null : _save,
                    icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                    label: Text(_saving ? 'Guardando…' : 'Guardar producto'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(onPressed: _saving ? null : () => _close(), child: const Text('Cancelar')),
                  if (_original != null) Padding(padding: const EdgeInsets.only(top: 20),
                    child: TextButton.icon(
                      onPressed: _saving ? null : _delete, icon: const Icon(Icons.delete_outline),
                      label: const Text('Eliminar producto'),
                      style: TextButton.styleFrom(foregroundColor: Colors.red.shade800),
                    )),
                  const SizedBox(height: 32),
                ],
              ))),
            )),
    ),
  );
}

class _PriceDialog extends StatefulWidget {
  const _PriceDialog({required this.product});
  final CatalogProduct product;
  @override
  State<_PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends State<_PriceDialog> {
  late final TextEditingController _controller;
  final _form = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: (widget.product.draft.priceCents / 100).toStringAsFixed(2));
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Cambiar precio'),
    content: Form(key: _form, child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(widget.product.draft.name),
      const SizedBox(height: 16),
      TextFormField(
        key: const ValueKey('quick-price'), controller: _controller, autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Nuevo precio (MXN)', prefixText: r'$ '),
        validator: (value) => parsePriceCents(value ?? '') == null
            ? 'Usa un precio positivo con hasta 2 decimales.' : null,
      ),
      const SizedBox(height: 12),
      const Text('El nuevo precio aplica a pedidos futuros.'),
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: () {
        if (_form.currentState!.validate()) Navigator.pop(context, parsePriceCents(_controller.text));
      }, child: const Text('Guardar precio')),
    ],
  );
}
