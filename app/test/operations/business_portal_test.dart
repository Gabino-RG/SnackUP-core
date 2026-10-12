import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:snackup/api/api_client.dart';
import 'package:snackup/catalog/local_catalog_repository.dart';
import 'package:snackup/features/operations/business_portal.dart';
import 'package:snackup/operations/operations_repository.dart';
import 'operations_repository_test.dart' show orderData;
void main(){
  testWidgets('mobile kitchen completes a verified delivery and navigates the integrated catalog',(tester)async{
    tester.view.physicalSize=const Size(390,900);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    var delivered=false;var attempts=0;
    final api=ApiClient(baseUri:Uri.parse('https://test.example/api/v1/'),client:MockClient((request)async{
      Object d;
      if(request.url.path.endsWith('/businesses/b1')){d={'id':'b1','name':'Central','isOpen':true,'version':1};}
      else if(request.url.path.endsWith('/complete')){attempts++;expect(jsonDecode(request.body)['code'],'4821');delivered=true;d=orderData(status:'completed',version:2);}
      else{d={'data':delivered?[]:[orderData(status:'ready')]};}
      return http.Response(jsonEncode(d),200,headers:{'content-type':'application/json; charset=utf-8'});
    }));
    await tester.pumpWidget(MaterialApp(home:BusinessPortal(businessId:'b1',catalog:LocalCatalogRepository(MemoryCatalogStore()),repository:OperationsRepository(api),token:()async=>'a',onSignOut:(){},enableRealtime:false)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Listos (1)'));await tester.pumpAndSettle();
    await tester.tap(find.text('Verificar entrega'));await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar entrega'));await tester.pumpAndSettle();expect(attempts,0);
    await tester.enterText(find.byKey(const ValueKey('delivery-code')),'4821');await tester.tap(find.text('Confirmar entrega'));await tester.pumpAndSettle();
    expect(delivered,true);expect(find.text('Pedido #101'),findsNothing);
    await tester.tap(find.text('Productos'));await tester.pumpAndSettle();expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
