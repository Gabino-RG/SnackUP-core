import 'package:flutter/material.dart';

/// Starts the app only after its required services are ready.
class SnackUpBootstrap extends StatefulWidget {
  final Future<void> Function() initialize;
  final Widget child;

  const SnackUpBootstrap({
    super.key,
    required this.initialize,
    required this.child,
  });

  @override
  State<SnackUpBootstrap> createState() => _SnackUpBootstrapState();
}

class _SnackUpBootstrapState extends State<SnackUpBootstrap> {
  late Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = Future<void>.sync(widget.initialize);
  }

  void _retry() {
    setState(() {
      _initialization = Future<void>.sync(widget.initialize);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        final failed =
            snapshot.connectionState == ConnectionState.done &&
            snapshot.hasError;
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          return widget.child;
        }

        return MaterialApp(
          title: 'SnackUp UTSJR',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF4A54DF),
            ),
          ),
          home: Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (failed) ...[
                        const Icon(Icons.cloud_off_rounded, size: 48),
                        const SizedBox(height: 16),
                        const Text(
                          'No pudimos iniciar SnackUP',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Revisa tu conexión e intenta de nuevo. Si el problema continúa, contacta al equipo de SnackUP.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _retry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                        ),
                      ] else ...[
                        const CircularProgressIndicator(),
                        const SizedBox(height: 24),
                        const Text('Iniciando SnackUP…'),
                      ],
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
}
