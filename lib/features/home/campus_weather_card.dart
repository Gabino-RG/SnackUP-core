import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../user/product_detail_screen.dart';

class CampusWeatherCard extends StatefulWidget {
  const CampusWeatherCard({super.key});

  @override
  State<CampusWeatherCard> createState() => _CampusWeatherCardState();
}

class _CampusWeatherCardState extends State<CampusWeatherCard> {
  static const _latitude = String.fromEnvironment(
    'SNACKUP_CAMPUS_LATITUDE',
    defaultValue: '20.36778',
  );
  static const _longitude = String.fromEnvironment(
    'SNACKUP_CAMPUS_LONGITUDE',
    defaultValue: '-100.010095',
  );

  static ({double temperature, int code, DateTime fetchedAt})? _cached;
  late final _weather = _load();
  late final _openBusinesses = FirebaseFirestore.instance
      .collection('businesses')
      .where('isOpen', isEqualTo: true)
      .snapshots();
  late final _availableProducts = FirebaseFirestore.instance
      .collection('products')
      .where('isAvailable', isEqualTo: true)
      .snapshots();

  Future<({double temperature, int code, DateTime fetchedAt})?> _load() async {
    final cached = _cached;
    final age = cached == null
        ? null
        : DateTime.now().difference(cached.fetchedAt);
    if (age != null && age < const Duration(minutes: 15)) return cached;

    final client = http.Client();
    try {
      final response = await client
          .get(
            Uri.https('api.open-meteo.com', '/v1/forecast', {
              'latitude': _latitude,
              'longitude': _longitude,
              'current': 'temperature_2m,weather_code',
            }),
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final current = (jsonDecode(response.body) as Map)['current'] as Map;
        final temperature = (current['temperature_2m'] as num).toDouble();
        final code = current['weather_code'] as int;
        if (temperature.isFinite) {
          return _cached = (
            temperature: temperature,
            code: code,
            fetchedAt: DateTime.now(),
          );
        }
      }
    } on Exception {
      // The menu stays usable if weather is unavailable.
    } on TypeError {
      // Unexpected response shape.
    } finally {
      client.close();
    }
    return age != null && age < const Duration(hours: 1) ? cached : null;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _openBusinesses,
      builder: (context, businessesSnapshot) {
        final businesses = businessesSnapshot.data?.docs;
        if (businessesSnapshot.hasError ||
            businesses == null ||
            businesses.isEmpty) {
          return const SizedBox.shrink();
        }
        final openBusinessIds = businesses.map((doc) => doc.id).toSet();
        return StreamBuilder(
          stream: _availableProducts,
          builder: (context, productsSnapshot) {
            final products = productsSnapshot.data?.docs.where((doc) {
              final data = doc.data();
              final stock = data['stock'];
              final name = data['name'];
              return openBusinessIds.contains(data['businessId']) &&
                  stock is int &&
                  stock > 0 &&
                  name is String &&
                  name.trim().isNotEmpty;
            }).toList();
            if (productsSnapshot.hasError ||
                products == null ||
                products.isEmpty) {
              return const SizedBox.shrink();
            }
            return _buildSuggestion(products);
          },
        );
      },
    );
  }

  Widget _buildSuggestion(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> products,
  ) {
    return FutureBuilder(
      future: _weather,
      builder: (context, snapshot) {
        final weather = snapshot.data;
        final code = weather?.code ?? -1;
        final (label, climateIcon, colors, preferredFoods) = switch (code) {
          >= 51 => (
            code >= 95 ? 'Tormenta' : 'Precipitación',
            Icons.umbrella_outlined,
            const [Color(0xFF342569), Color(0xFF51488E)],
            RegExp(r'caldo|sopa|consom[eé]|tamal|quesadilla|pozole'),
          ),
          _ when (weather?.temperature ?? 0) >= 24 => (
            code == 0 ? 'Soleado' : 'Tiempo cálido',
            Icons.wb_sunny_outlined,
            const [Color(0xFF9A3A13), Color(0xFF854719)],
            RegExp(r'ensalada|fruta|wrap|yogur|s[aá]ndwich|gelatina'),
          ),
          _ when weather != null && weather.temperature < 18 => (
            code == 45 || code == 48 ? 'Niebla' : 'Tiempo fresco',
            Icons.ac_unit_outlined,
            const [Color(0xFF16435A), Color(0xFF245674)],
            RegExp(
              r'caldo|sopa|pozole|torta|chilaquil|mollete|tamal|quesadilla',
            ),
          ),
          _ => (
            weather == null
                ? ''
                : (code == 0 ? 'Despejado' : 'Tiempo templado'),
            Icons.cloud_outlined,
            const [Color(0xFF343185), Color(0xFF59409A)],
            null,
          ),
        };

        final now = DateTime.now();
        final day = DateTime.utc(now.year, now.month, now.day);
        String searchableText(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
          final data = doc.data();
          return [
            data['name'],
            data['category'],
          ].whereType<String>().join(' ').toLowerCase();
        }

        final meals = products.where((doc) {
          final category = doc.data()['category'];
          return category is! String ||
              !RegExp(
                r'bebida|refresco|jugo|caf[eé]',
              ).hasMatch(category.toLowerCase());
        }).toList();
        if (meals.isEmpty) return const SizedBox.shrink();
        final matches = meals
            .where(
              (doc) => preferredFoods?.hasMatch(searchableText(doc)) ?? false,
            )
            .toList();
        final candidates = matches.isEmpty ? meals : matches;
        candidates.sort((a, b) => a.id.compareTo(b.id));
        final selected =
            candidates[day.difference(DateTime.utc(2026)).inDays %
                candidates.length];
        final product = selected.data();
        final theme = Theme.of(context).textTheme;

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.restaurant_outlined,
                  size: 26,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (weather != null) ...[
                      Row(
                        children: [
                          Icon(climateIcon, size: 15, color: Colors.white),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              '$label · ${weather.temperature.toStringAsFixed(0)} °C',
                              style: theme.labelMedium?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      'Sugerencia del día',
                      style: theme.labelMedium?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      product['name'] as String,
                      style: theme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => ProductDetailScreen(
                            product: product,
                            productId: selected.id,
                          ),
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text('Ver platillo'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
