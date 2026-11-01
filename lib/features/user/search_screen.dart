import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snackup/student/student_api.dart';
import 'package:snackup/student/student_widgets.dart';
import 'package:snackup/theme/student_colors.dart';
import 'package:snackup/theme/student_text.dart';

import 'menu_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  StudentApi? _api;
  int _revision = -1;
  String _query = '';
  Future<List<Map<String, dynamic>>>? _results;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = context.watch<StudentApi>();
    if (_api != api || _revision != api.revision) {
      _api = api;
      _revision = api.revision;
      if (_query.isNotEmpty) _results = _fetch(_query);
    }
  }

  Future<List<Map<String, dynamic>>> _fetch(String query) =>
      _api!.getAll('/products/search', query: {'q': query});

  void _changed(String value) {
    _debounce?.cancel();
    final query = value.trim();
    // Detach the previous Future immediately so a slower old search cannot win.
    setState(() {
      _query = query;
      _results = null;
    });
    if (query.isNotEmpty) {
      _debounce = Timer(const Duration(milliseconds: 350), () {
        if (!mounted || _query != query) return;
        setState(() {
          _results = _fetch(query);
        });
      });
    }
  }

  void _searchNow() {
    _debounce?.cancel();
    final query = _controller.text.trim();
    setState(() {
      _query = query;
      _results = query.isEmpty ? null : _fetch(query);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 940),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Encuentra tu antojo', style: AppText.h1),
                    const SizedBox(height: 8),
                    const Text(
                      'Busca productos en todas tus cafeterías.',
                      style: AppText.notes,
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _controller,
                      onChanged: _changed,
                      onSubmitted: (_) => _searchNow(),
                      maxLength: 160,
                      textInputAction: TextInputAction.search,
                      style: AppText.body,
                      decoration: InputDecoration(
                        hintText: '¿Qué te gustaría comer?',
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: AppColors.primary,
                        ),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Limpiar búsqueda',
                                onPressed: () {
                                  _controller.clear();
                                  _changed('');
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                        counterText: '',
                        filled: true,
                        fillColor: AppColors.componentBase,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _query.isEmpty
                    ? const Center(
                        child: CatalogEmpty(
                          icon: Icons.manage_search_rounded,
                          title: 'Tu siguiente favorito está aquí',
                          message:
                              'Escribe el nombre de un producto para empezar.',
                        ),
                      )
                    : _results == null
                    ? const Center(child: CircularProgressIndicator())
                    : FutureBuilder<List<Map<String, dynamic>>>(
                        future: _results,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState != ConnectionState.done) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (snapshot.hasError) {
                            return ErrorPanel(
                              error: snapshot.error!,
                              onRetry: _searchNow,
                            );
                          }
                          final products = snapshot.data!;
                          if (products.isEmpty) {
                            return const Center(
                              child: CatalogEmpty(
                                icon: Icons.search_off_rounded,
                                title: 'No encontramos productos',
                                message:
                                    'Prueba otro nombre o explora los menús desde Inicio.',
                              ),
                            );
                          }
                          return ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                            itemCount: products.length + 1,
                            itemBuilder: (context, index) => index == 0
                                ? Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: Text(
                                      '${products.length} resultados para “$_query”',
                                      style: AppText.notes,
                                    ),
                                  )
                                : CatalogProductCard(
                                    product: products[index - 1],
                                  ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
