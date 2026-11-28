import 'dart:convert';

import 'package:http/http.dart' as http;

class WeatherReading {
  final double temperature;
  final int code;
  final DateTime fetchedAt;

  const WeatherReading({
    required this.temperature,
    required this.code,
    required this.fetchedAt,
  });
}

/// Open-Meteo access with a session cache shared by the app's weather cards.
class WeatherService {
  static final instance = WeatherService();

  static const _latitude = String.fromEnvironment(
    'SNACKUP_CAMPUS_LATITUDE',
    defaultValue: '20.36778',
  );
  static const _longitude = String.fromEnvironment(
    'SNACKUP_CAMPUS_LONGITUDE',
    defaultValue: '-100.010095',
  );

  final http.Client? _client;
  final DateTime Function() _clock;
  final Duration _timeout;
  WeatherReading? _cached;

  /// An injected client remains owned by its caller and is not closed here.
  WeatherService({
    http.Client? client,
    DateTime Function()? clock,
    Duration timeout = const Duration(seconds: 5),
  }) : _client = client,
       _clock = clock ?? DateTime.now,
       _timeout = timeout;

  Future<WeatherReading?> load() async {
    final cached = _cached;
    if (cached != null && _isYoungerThan(cached, const Duration(minutes: 15))) {
      return cached;
    }

    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(
            Uri.https('api.open-meteo.com', '/v1/forecast', {
              'latitude': _latitude,
              'longitude': _longitude,
              'current': 'temperature_2m,weather_code',
            }),
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final current = data is Map ? data['current'] : null;
        final temperature = current is Map ? current['temperature_2m'] : null;
        final code = current is Map ? current['weather_code'] : null;
        if (temperature is num && temperature.isFinite && code is int) {
          return _cached = WeatherReading(
            temperature: temperature.toDouble(),
            code: code,
            fetchedAt: _clock(),
          );
        }
      }
    } on Exception {
      // Network failures, timeouts and invalid JSON do not block the menu.
    } finally {
      if (_client == null) client.close();
    }

    return cached != null && _isYoungerThan(cached, const Duration(hours: 1))
        ? cached
        : null;
  }

  bool _isYoungerThan(WeatherReading reading, Duration duration) {
    final age = _clock().difference(reading.fetchedAt);
    return !age.isNegative && age < duration;
  }
}
