# Ejecutar las cinco pruebas de SnackUp

Desde la carpeta SnackUP-core, en la rama codex/pruebas-flutter:

```powershell
flutter pub get
flutter test test/snackup_test.dart --reporter expanded
```

Para guardar evidencia:

```powershell
flutter test test/snackup_test.dart --reporter expanded 2>&1 | Tee-Object -FilePath resultados_pruebas.txt
```

El archivo test/snackup_test.dart contiene cinco pruebas con ARRANGE, ACT y ASSERT. Usa Firebase Auth y Firestore simulados; no necesitas iniciar sesión en Firebase ni un dispositivo. Las pantallas aceptan dependencias opcionales para probarse; al abrirse normalmente siguen usando Firebase.

Casos: aumentar cantidad; respetar cantidad mínima; calcular total decimal; rechazar un carrito de varias tiendas; crear un pedido válido y vaciar el carrito.

Ejecuta el archivo indicado: test/widget_test.dart es una prueba anterior del contador de ejemplo y no corresponde a estas pantallas.

Un resultado con cinco pruebas aprobadas termina con All tests passed. Si falla una prueba, conserva la salida y documenta el error sin marcarla como aprobada.

## Resultado verificado
Ejecución local del 20 de octubre de 2026 con Flutter 3.32.4 y Dart 3.8.1.

| Caso | Resultado obtenido | Estado |
|---|---|---|
| CP-01 | Cantidad 2 y total $50.00 | Aprobado |
| CP-02 | Cantidad 1 después de intentar disminuir dos veces | Aprobado |
| CP-03 | Total $55.50 para tres unidades de $18.50 | Aprobado |
| CP-04 | Mensaje de rechazo, sin pedidos nuevos y dos productos conservados | Aprobado |
| CP-05 | Pedido de $65.00 con datos esperados y carrito vacío | Aprobado |

Salida final: `00:05 +5: All tests passed!`
Evidencia completa: resultados_pruebas.txt.

Alcance: son pruebas de widgets con servicios simulados. Comprueban interacción y lógica de estas pantallas; no verifican reglas de seguridad ni conectividad del servicio Firebase real.
