# Registro institucional UTSJR

El dominio confirmado por el equipo es `utsjr.edu.mx`. La compilación normal
acepta únicamente ese dominio en registro, acceso y recuperación de alumnos.
Los dominios parecidos, subdominios, Gmail y los correos ficticios se rechazan.
No se compila con `SNACKUP_LOCAL_DEMO=true` en el modo institucional.

El frontend valida en `lib/student/email_policy.dart`. En la versión anterior
con Firebase, el filtro estaba en el validador del correo del formulario
`lib/features/auth/register_screen.dart`; no era una consulta al padrón universitario.

El backend existente configura la restricción en su archivo privado `backend/.env`:

```dotenv
SNACKUP_STUDENT_EMAIL_DOMAINS=utsjr.edu.mx
```

El registro también exige una coincidencia activa de correo y matrícula en
`academic_records` y la confirmación del correo. El dominio no sustituye esos
requisitos. Las cuentas antiguas de Firebase no se importan automáticamente.

## Estado de esta instalación local

- Dominio de registro configurado: `utsjr.edu.mx`.
- Indicaciones de prueba retiradas de la compilación institucional.
- Dos identidades ficticias de la prueba anterior desactivadas mediante la
  importación existente, que también revoca sus sesiones.
- Se añadió un único alumno con los datos proporcionados y autorizados por el
  usuario, mediante el importador existente. Al comprobar el catálogo se
  verificó que su correo ya estaba confirmado. Los datos personales y la contraseña no se incluyen
  en esta entrega de código.
- No se ha proporcionado un padrón completo de la universidad.
- El SMTP sigue apuntando al buzón Mailpit local: no envía correos reales.

Se comprobó el alta de esa cuenta, la recepción de su mensaje en Mailpit y su
posterior acceso con el correo confirmado por el usuario. Todavía no se ha
comprobado la entrega a un buzón institucional real.
El acuse genérico del backend no acredita que la cuenta haya sido creada.

Se mantiene el requisito de padrón por decisión del equipo. El formulario lo
explica antes de pedir los datos y conserva el acuse condicional del servidor.
No se habilita el registro sin padrón ni se crean autorizaciones desde el frontend.

## Datos que necesita configurar el equipo

1. El padrón autorizado, con las columnas y comandos que ya describe
   `backend/API_ALUMNOS.md`. Debe validarse con `import-roster --dry-run`
   antes de importarlo. No se deben inventar matrículas ni carreras.
2. El servicio SMTP autorizado mediante `SNACKUP_SMTP_HOST`,
   `SNACKUP_SMTP_PORT`, `SNACKUP_SMTP_FROM`, `SNACKUP_SMTP_USER`,
   `SNACKUP_SMTP_PASSWORD` y `SNACKUP_SMTP_STARTTLS` según el proveedor.
   Las credenciales se configuran localmente; no se suben a Git ni se pegan en el chat.
3. Reiniciar FastAPI tras modificar su configuración y verificar el recorrido
   con un alumno autorizado que confirme su propio correo.

Para compilar la interfaz institucional, desde la raíz del proyecto:

```powershell
flutter build web --release --no-pub --no-web-resources-cdn --pwa-strategy=none
```

El código del backend, sus migraciones y las pantallas de Cocina permanecen intactos.
