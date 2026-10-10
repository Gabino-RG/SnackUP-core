import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snackup/catalog/catalog.dart';
import 'package:snackup/catalog/local_catalog_repository.dart';
import 'package:snackup/features/catalog/catalog_screen.dart';

void main() {
  testWidgets('create product and change its price through real screens', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final repo = LocalCatalogRepository(MemoryCatalogStore());
    await tester.pumpWidget(MaterialApp(home: CatalogScreen(businessId:'local_1', repository: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-product')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('product-name')), 'Burrito');
    await tester.enterText(find.byKey(const ValueKey('product-category')), 'Alimentos');
    await tester.enterText(find.byKey(const ValueKey('product-price')), '42,50');
    await tester.ensureVisible(find.byKey(const ValueKey('save-product')));
    await tester.tap(find.byKey(const ValueKey('save-product')));
    await tester.pumpAndSettle();
    expect((await repo.list('local_1')).total, 4);
    expect(find.text('Burrito'), findsOneWidget);
    await tester.tap(find.byTooltip('Cambiar precio de Burrito'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('quick-price')), '48.00');
    await tester.tap(find.text('Guardar precio'));
    await tester.pumpAndSettle();
    final saved = (await repo.list('local_1', query: const CatalogQuery(search:'Burrito'))).items.single;
    expect(saved.draft.priceCents, 4800);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile catalog, validation and cancel preserve existing data', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final repo = LocalCatalogRepository(MemoryCatalogStore());
    await tester.pumpWidget(MaterialApp(home: CatalogScreen(businessId:'local_1', repository: repo)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('add-product')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('save-product')));
    await tester.tap(find.byKey(const ValueKey('save-product')));
    await tester.pumpAndSettle();
    expect(find.text('Completa este campo.'), findsWidgets);
    expect((await repo.list('local_1')).total, 3);
    await tester.ensureVisible(find.byKey(const ValueKey('product-name')));
    await tester.enterText(find.byKey(const ValueKey('product-name')), 'Sin guardar');
    await tester.tap(find.byTooltip('Volver al catálogo'));
    await tester.pumpAndSettle();
    expect(find.text('Cambios sin guardar'), findsOneWidget);
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect((await repo.list('local_1')).total, 3);
    expect(tester.takeException(), isNull);
  });
}
