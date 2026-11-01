# Crear una cuenta de alumno en la prueba local

> Esta guía corresponde a la prueba anterior. El modo actual usa `@utsjr.edu.mx`
> y las dos identidades ficticias se han desactivado. Consulta
> `REGISTRO_INSTITUCIONAL.md` para ver la configuración y lo que falta.

Abre **http://localhost:8000**, actualiza la página y pulsa **Crear cuenta de alumno**.

Usa el registro ficticio preparado para ti:

| Campo | Dato de prueba |
|---|---|
| Nombre | Alumno de demostración |
| Correo | alumno.demo@students.example.edu |
| Matrícula | DEMO-001 |
| Contraseña | Elige una de entre 12 y 128 caracteres. |

1. Abre y lee **Protección de Datos** y **Política de Privacidad**.
2. Marca la casilla de aceptación. **Crear cuenta** permanece deshabilitado hasta que la marques.
3. Pulsa **Crear cuenta**.
4. Abre **http://localhost:8025**, el buzón de correo de prueba.
5. Busca el correo dirigido a `alumno.demo@students.example.edu` y abre su enlace de confirmación.
6. Pulsa **Confirmar correo** en la página que abre el enlace.
7. Vuelve a **http://localhost:8000** e inicia sesión con ese correo y la contraseña que elegiste.

El correo se captura únicamente en tu PC: no se envía a Internet. Solo los datos
incluidos en el padrón ficticio permiten completar esta prueba. Usar otro correo
puede devolver el acuse genérico sin crear una cuenta, tal como establece el backend.

Se comprobó el recorrido completo con una segunda cuenta ficticia de control:
registro 202, recepción SMTP local, confirmación 204, login 200 con rol ALUMNO y
cierre de sesión 204. No se omitieron el padrón ni la verificación.

La nueva paleta del frontend de alumnos utiliza azul marino `#092E53`, verde lima
`#D9F129`, turquesa `#249CC0`, tarjetas blancas y fondo `#F6F8FA`. Se conservaron
intactos el código del backend, las pantallas de Cocina y sus archivos de tema.

La navegación ahora muestra Inicio, Pedidos, Favoritos y Perfil; Buscar y Carrito
están en la cabecera. No se añadieron saldos, descuentos, pagos confirmados ni
información nutricional que no provenga de la API.

Para arrancar otra vez, inicia Docker Desktop, `snackup-postgres` y
`snackup-correo-local`. Desde la carpeta raíz del proyecto, en terminales separadas:

```powershell
.\tools\iniciar_backend.ps1
```

```powershell
.\tools\abrir_alumnos.ps1 -SinCompilar
```

Si necesitas recompilar conservando las indicaciones de prueba del formulario:

```powershell
.\tools\abrir_alumnos.ps1 -DemoLocal
```

Para usar personas reales se necesita el padrón autorizado y el SMTP del equipo.
Esta configuración de demostración no habilita el registro institucional real.
