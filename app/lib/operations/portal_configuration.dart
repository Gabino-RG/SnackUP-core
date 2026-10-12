import '../api/api_client.dart';
import 'models.dart';

/// Names and account policy come from the server, never from review scores.
class PortalConfiguration {
  const PortalConfiguration({
    required this.universityName,
    required this.cafeteriaId,
    required this.cafeteriaName,
    required this.adminEmailDomains,
  });
  final String universityName, cafeteriaId, cafeteriaName;
  final List<String> adminEmailDomains;
  factory PortalConfiguration.fromJson(dynamic value) {
    final d = resource(value);
    final university = object(d['university']),
        cafeteria = object(d['cafeteria']);
    final domains = d['adminEmailDomains'];
    if (domains is! List ||
        domains.isEmpty ||
        domains.any(
          (v) =>
              v is! String ||
              !RegExp(r'^[a-z0-9]+(?:[.-][a-z0-9]+)+$').hasMatch(v),
        )) {
      throw const ApiException(
        'Falta la política de correos institucionales.',
        code: 'INVALID_RESPONSE',
      );
    }
    return PortalConfiguration(
      universityName: requiredText(university, 'name'),
      cafeteriaId: requiredText(cafeteria, 'id'),
      cafeteriaName: requiredText(cafeteria, 'name'),
      adminEmailDomains: List<String>.unmodifiable(domains),
    );
  }
  bool acceptsAdminEmail(String email) {
    final parts = email.trim().toLowerCase().split('@');
    return parts.length == 2 &&
        parts.first.isNotEmpty &&
        adminEmailDomains.contains(parts.last);
  }
}
