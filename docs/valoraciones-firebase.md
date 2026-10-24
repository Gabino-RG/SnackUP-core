# Publicar los permisos de las valoraciones

Las reglas compartidas del proyecto no contienen permisos para `reviews` ni `restaurant_reviews`. Por eso Firestore rechaza las escrituras aunque el dispositivo tenga internet. El mensaje anterior atribuía cualquier excepción a la conexión.

## Corrección

1. Abrir el proyecto **snackup-8fe96** en Firebase Console.
2. Entrar a **Firestore Database > Reglas**.
3. Copiar todo el contenido de `firestore.rules` de esta rama y reemplazar el texto del editor.
4. Pulsar **Publicar** y volver a intentar la valoración.

El archivo conserva los permisos que compartiste de usuarios, negocios, productos, pedidos y chats; agrega los dos bloques de valoraciones. Permite lecturas públicas y valida para las escrituras: sesión, propietario del pedido completado, restaurante del pedido, estrellas de 1 a 5 y comentario de hasta 300 caracteres. Cada persona puede modificar su propia valoración. La app comprueba además que el platillo esté en su pedido.

No se publicó nada en Firebase desde esta tarea. Las reglas se revisaron como código; no se ejecutaron en el emulador porque no se autorizó su descarga. Las pruebas de Flutter no equivalen a una verificación de permisos del servidor.

## App

La pantalla distingue errores de permisos, sesión, servicio y validación. Conserva el comentario si falla el envío y muestra un código que se puede copiar; en desarrollo registra el detalle en la consola.

## Existencias

El menú de inicio, las promociones, el menú por cafetería y la búsqueda excluyen los productos con `stock <= 0`, sin existencias definidas o no disponibles. Los menús y promociones se actualizan con el inventario en tiempo real. Si vuelve a haber existencias, el producto vuelve a mostrarse. Los pedidos e historial se conservan.
