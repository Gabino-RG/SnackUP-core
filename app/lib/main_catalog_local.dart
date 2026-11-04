import 'package:flutter/material.dart';
import 'catalog/catalog.dart';
import 'catalog/local_catalog_repository.dart';
import 'catalog/preferences_catalog_store.dart';
import 'features/catalog/catalog_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(CatalogLocalApp(repository: LocalCatalogRepository(PreferencesCatalogStore())));
}

/// Same catalog screens as the integrated application, without a production session.
class CatalogLocalApp extends StatefulWidget {
  const CatalogLocalApp({super.key, required this.repository});
  final CatalogRepository repository;
  @override
  State<CatalogLocalApp> createState() => _CatalogLocalAppState();
}

class _CatalogLocalAppState extends State<CatalogLocalApp> {
  int _local = 1;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SnackUP · Catálogo local', debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true, fontFamily: 'Inter',
      colorScheme: ColorScheme.fromSeed(seedColor: catalogNavy),
      scaffoldBackgroundColor: catalogBackground,
      appBarTheme: const AppBarTheme(backgroundColor: catalogBackground, foregroundColor: catalogNavy),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: catalogNavy, foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16))),
    ),
    home: Scaffold(
      appBar: AppBar(
        title: const Text('SnackUP · Negocios', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        actions: [
          DropdownButton<int>(
            value: _local, underline: const SizedBox.shrink(),
            items: [for (var i = 1; i <= 4; i++) DropdownMenuItem(value: i, child: Text('Local $i'))],
            onChanged: (value) { if (value != null) setState(() => _local = value); },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: CatalogScreen(key: ValueKey(_local), businessId: 'local_$_local', repository: widget.repository),
    ),
  );
}
