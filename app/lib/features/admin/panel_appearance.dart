import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PanelAppearance extends ChangeNotifier {
  static const preferenceKey = 'snackup.panels.darkBlue';
  bool dark = false;
  bool _disposed = false;
  int _revision = 0;
  Future<void> _saving = Future.value();

  Future<void> restore() async {
    final revision = _revision;
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!_disposed && revision == _revision) {
        dark = preferences.getBool(preferenceKey) ?? false;
        notifyListeners();
      }
    } catch (_) {
      // Storage can be unavailable in private browsing; the switch still works.
    }
  }

  void toggle() {
    dark = !dark;
    _revision++;
    final value = dark;
    notifyListeners();
    _saving = _saving.then((_) async {
      try {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setBool(preferenceKey, value);
      } catch (_) {
        // Keep the selected appearance for this session.
      }
    });
  }

  Future<void> get saved => _saving;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class PanelAppearanceScope extends InheritedNotifier<PanelAppearance> {
  const PanelAppearanceScope({
    super.key,
    required PanelAppearance controller,
    required super.child,
  }) : super(notifier: controller);
}

class PanelThemeButton extends StatelessWidget {
  const PanelThemeButton({super.key});

  @override
  Widget build(BuildContext context) {
    final appearance = context
        .dependOnInheritedWidgetOfExactType<PanelAppearanceScope>()
        ?.notifier;
    if (appearance == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: appearance.dark ? 'Activar modo claro' : 'Activar modo oscuro',
      onPressed: appearance.toggle,
      icon: Icon(
        appearance.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
      ),
    );
  }
}
