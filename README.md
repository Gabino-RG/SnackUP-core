# SnackUP · integración local de Alumnos, Cocina y Administración

Esta rama reúne las tres interfaces con el mismo backend y una base PostgreSQL
persistente para probar el sistema en una laptop. La guía vigente de esta copia
es [INTEGRACION_LOCAL.md](INTEGRACION_LOCAL.md): incluye inicio, parada, cuentas
ficticias, pruebas y límites pendientes de validar en el servidor definitivo.

## Frontend de alumnos REST

La interfaz de alumnos se conecta al backend FastAPI existente mediante `/api/v1`.
Consulta [ALUMNOS_REST.md](ALUMNOS_REST.md) para instalar, ejecutar, probar e integrar
esta interfaz con el contenedor de tu equipo. El backend y las pantallas de Cocina
se conservan sin cambios.

Las instrucciones de Firebase que siguen son documentación histórica del proyecto
original. El arranque actual del portal de alumnos utiliza REST.

---

# SnackUP-Core `v1.0` · documentación original

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
