import 'dart:async';
import 'package:flutter/material.dart';

/// Keeps startup visible and recoverable when Firebase cannot initialize.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({
    super.key,
    required this.initialize,
    required this.appBuilder,
    this.timeout = const Duration(seconds: 25),
    this.onReload,
  });

  final Future<void> Function() initialize;
  final Widget Function() appBuilder;
  final Duration timeout;
  final VoidCallback? onReload;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late Future<void> _initialization;
  late Future<void> _visibleAttempt;
  bool _attemptFinished = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _attemptFinished = false;
    _initialization = Future<void>.sync(widget.initialize).whenComplete(() {
      _attemptFinished = true;
    });
    _visibleAttempt = _initialization.timeout(widget.timeout);
  }

  void _retry() {
    setState(() {
      if (_attemptFinished) {
        _start();
      } else {
        // A slow SDK loader may still be running. Do not initialize it twice.
        _visibleAttempt = _initialization.timeout(widget.timeout);
      }
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _visibleAttempt,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          !snapshot.hasError) {
        return widget.appBuilder();
      }
      return MaterialApp(
        title: 'SnackUp UTSJR',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'Inter', useMaterial3: true),
        home: Scaffold(
          backgroundColor: const Color(0xFFF8F9FA),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.restaurant_rounded,
                      size: 48,
                      color: Color(0xFF002654),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      snapshot.hasError
                          ? 'No pudimos iniciar SnackUp'
                          : 'Iniciando SnackUp',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (snapshot.hasError) ...[
                      Text(
                        snapshot.error is UnsupportedError
                            ? 'Esta plataforma aún no está configurada. Abre la versión web en tu navegador.'
                            : 'Comprueba tu conexión a internet y vuelve a intentar.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        // A failed JS dynamic import may never complete in
                        // FlutterFire. A fresh document restarts its SDK loader.
                        onPressed: !_attemptFinished && widget.onReload != null
                            ? widget.onReload
                            : _retry,
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          !_attemptFinished && widget.onReload != null
                              ? 'Recargar aplicación'
                              : 'Reintentar',
                        ),
                      ),
                    ] else
                      const CircularProgressIndicator(),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
