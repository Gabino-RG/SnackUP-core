# SnackUP · usuarios / PWA

Rama `codex/usuarios-pwa`, derivada del `main` real en `b7abff6`. Tiene su propio
Dockerfile, contenedor `snackup-usuarios` y workflow de construcción.

- [Construir y ejecutar la PWA](deploy/README.md).
- [Backend independiente](https://github.com/Gabino-RG/SnackUP-core/tree/codex/backend-api-v3-fastapi).
- [Cocina y Administración](https://github.com/Gabino-RG/SnackUP-core/tree/codex/entrega-paneles-rest).
- [Despliegue de las tres aplicaciones](https://github.com/Gabino-RG/SnackUP-core/blob/codex/backend-api-v3-fastapi/backend/DESPLIEGUE_TRES_APPS.md).
- [Auditoría para la integración REST](https://github.com/Gabino-RG/SnackUP-core/blob/codex/backend-api-v3-fastapi/backend/AUDITORIA_APP_Y_API_V3_2.md).

Esta versión conserva la integración existente con Firebase y las pantallas
históricas de Cocina que el propietario retirará en otro cambio. Docker no
sustituye sus repositorios por FastAPI. La PWA permite instalación y una página
genérica sin conexión; las operaciones con datos requieren conexión.

El contenedor compila con Flutter 3.32.0 fijado por digest y sirve los archivos
con Caddy 2.11.7 como usuario sin privilegios. No incluye el SDK en producción.
`main`, `develop` y la rama de respaldo se mantienen sin cambios.

## Documento heredado de main

Las notas siguientes describen el proyecto Firebase original. Para construir
esta rama con versiones verificables, usar las instrucciones de `deploy/README.md`.
La condición de producción y la capacidad requieren validación del entorno.


![SnackUP Banner](https://img.shields.io/badge/SnackUP-Official_Production_Repo-orange?style=for-the-badge&logo=fastapi)
[![Flutter Version](https://img.shields.io/badge/Flutter-3.29.0%2B-02569B?style=flat&logo=flutter)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Backend-Firebase-FFCA28?style=flat&logo=firebase&logoColor=black)](https://firebase.google.com)

Bienvenido al repositorio central de **SnackUP**. Esta es la versión profesional destinada a producción, optimizada para escalabilidad y rendimiento.

---

## ⚠️ Regla de Oro (Políticas de Git)

> **Prohibido hacer push directo a `main` o `develop`.**
> Todo cambio debe integrarse mediante **Pull Request (PR)** y requiere al menos **1 aprobación** de un socio para ser fusionado.

---

## 🛠️ Stack Tecnológico

| Componente | Tecnología | Detalle |
| :--- | :--- | :--- |
| **Framework** | Flutter 3.29.0+ | UI Multiplataforma |
| **Lenguaje** | Dart (SDK >=3.8.0) | Tipado fuerte |
| **Backend** | Firebase | Firestore, Auth, Storage |
| **Estado** | Provider | ChangeNotifiers |

---

## 📋 Requisitos Previos

Para que el proyecto compile a la primera, es **obligatorio**:

1. **Actualizar Flutter:**

```bash
flutter upgrade
```

Verifica con `flutter --version` que estés en la 3.29.0 o superior.

2. **Firebase CLI:**

```bash
npm install -g firebase-tools
firebase login
```

---

## ⚙️ Configuración Inicial

Si es la primera vez que clonas el repo, sigue este orden exacto:

1. **Obtener dependencias:**

```bash
flutter pub get
```

2. **Vincular Firebase:**

```bash
flutterfire configure
```

Selecciona el proyecto **snackup-official** cuando el terminal te lo solicite.

3. **Limpieza (Solo si algo falla):**

```bash
flutter clean && flutter pub get
```

---

## 🌿 Flujo de Trabajo (GitFlow Pro)

Para mantener el código limpio y profesional, seguimos este estándar:

| Acción | Rama / Prefijo | Ejemplo de Commit |
| :--- | :--- | :--- |
| **Nueva Mejora** | `feat/` | `feat: add qr scanner integration` |
| **Arreglo de Bug** | `fix/` | `fix: resolve login timeout` |
| **Refactor** | `refactor/` | `refactor: optimize provider logic` |

> [!TIP]
> **Antes de empezar cualquier tarea:** Asegúrate de estar al día ejecutando `git pull origin develop` para evitar conflictos de merge.

---

## 📁 Estructura del Proyecto

```text
lib/
├── models/      # Definición de datos (Data classes)
├── services/    # Lógica de Firebase y APIs externas
├── providers/   # Manejo de estado global (ChangeNotifiers)
├── screens/     # Pantallas principales de la UI
└── widgets/     # Componentes reutilizables
```

---

<p align="center">
Desarrollado con ❤️ por el equipo de <strong>SnackUP</strong>
</p>
