import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:snackup/services/weather_service.dart';

const validWeather = '{"current":{"temperature_2m":25.5,"weather_code":0}}';

void main() {
  test('consulta Open-Meteo por HTTPS y convierte la respuesta', () async {
    final now = DateTime.utc(2026, 11, 27, 12);
    final client = MockClient((request) async {
      expect(request.url.scheme, 'https');
      expect(request.url.host, 'api.open-meteo.com');
      expect(request.url.path, '/v1/forecast');
      expect(
        request.url.queryParameters['current'],
        'temperature_2m,weather_code',
      );
      expect(request.url.queryParameters['latitude'], isNotEmpty);
      expect(request.url.queryParameters['longitude'], isNotEmpty);
      return http.Response(validWeather, 200);
    });
    addTearDown(client.close);

    final weather = await WeatherService(
      client: client,
      clock: () => now,
    ).load();
    expect(weather?.temperature, 25.5);
    expect(weather?.code, 0);
    expect(weather?.fetchedAt, now);
  });

  test('reutiliza el dato durante 15 minutos sin otra petición', () async {
    var now = DateTime.utc(2026, 11, 27, 12);
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response(validWeather, 200);
    });
    addTearDown(client.close);
    final service = WeatherService(client: client, clock: () => now);

    final first = await service.load();
    now = now.add(const Duration(minutes: 14, seconds: 59));
    expect(await service.load(), same(first));
    expect(requests, 1);

    now = now.add(const Duration(seconds: 1));
    await service.load();
    expect(requests, 2);
  });

  test('un fallo conserva el último dato válido menor de una hora', () async {
    var now = DateTime.utc(2026, 11, 27, 12);
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      if (requests > 1) throw http.ClientException('Sin conexión');
      return http.Response(validWeather, 200);
    });
    addTearDown(client.close);
    final service = WeatherService(client: client, clock: () => now);

    final first = await service.load();
    now = now.add(const Duration(minutes: 59, seconds: 59));
    expect(await service.load(), same(first));
    expect(requests, 2);

    now = now.add(const Duration(seconds: 1));
    expect(await service.load(), isNull);
    expect(requests, 3);
  });

  test('sin dato previo devuelve null cuando no hay conexión', () async {
    final client = MockClient(
      (_) async => throw http.ClientException('Sin conexión'),
    );
    addTearDown(client.close);

    expect(await WeatherService(client: client).load(), isNull);
  });

  test('rechaza HTTP no exitoso y respuestas con datos inválidos', () async {
    final responses = [
      http.Response(validWeather, 503),
      http.Response('no es JSON', 200),
      http.Response('[]', 200),
      http.Response('{"current":null}', 200),
      http.Response(
        '{"current":{"temperature_2m":"25","weather_code":0}}',
        200,
      ),
      http.Response(
        '{"current":{"temperature_2m":25,"weather_code":"sol"}}',
        200,
      ),
      http.Response(
        '{"current":{"temperature_2m":1e999,"weather_code":0}}',
        200,
      ),
    ];
    for (final response in responses) {
      final client = MockClient((_) async => response);
      addTearDown(client.close);
      expect(await WeatherService(client: client).load(), isNull);
    }
  });

  test('el timeout devuelve null y permite continuar sin clima', () async {
    final pending = Completer<http.Response>();
    final client = MockClient((_) => pending.future);
    addTearDown(client.close);

    final service = WeatherService(
      client: client,
      timeout: const Duration(milliseconds: 10),
    );
    expect(await service.load(), isNull);
  });

  test('una respuesta inválida no sustituye la caché válida', () async {
    var now = DateTime.utc(2026, 11, 27, 12);
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response(requests == 1 ? validWeather : '{}', 200);
    });
    addTearDown(client.close);
    final service = WeatherService(client: client, clock: () => now);

    final first = await service.load();
    now = now.add(const Duration(minutes: 20));
    expect(await service.load(), same(first));
  });
}
