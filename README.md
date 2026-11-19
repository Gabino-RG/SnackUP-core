# SnackUP-Core `v1.0`

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

## Sprint 9 · Panel Negocio y clima

- Las cuentas de negocio se asignan desde Firebase con el rol `business` en
  `users/{uid}` y la propiedad `ownerId` en `businesses/{businessId}`.
- En checkout se validan stock, precio y total con los datos de Firestore. El
  límite es de ocho productos distintos por pedido para respetar el límite de
  lecturas de Firestore Rules. El stock sigue siendo administrado por Negocio.
- Inicio sugiere un platillo disponible del menú de negocios abiertos, con preferencia según el clima. Open-Meteo recibe las coordenadas
  fijas del campus y la selección de variables climáticas. El menú carga por
  separado. Si el servicio falla, la sugerencia usa el último dato válido de
  la sesión durante una hora o muestra una sugerencia general.
- Antes de publicar las reglas e índices, prueba los dos roles en un proyecto
  de Firebase de prueba. La carpeta incluye el archivo de reglas y los índices.

Pruebas de permisos en el emulador, con Firebase CLI, Java y Node.js 22:

```powershell
firebase emulators:exec --only firestore --project demo-snackup-sprint9 "node test/firestore_sprint9.mjs"
```
