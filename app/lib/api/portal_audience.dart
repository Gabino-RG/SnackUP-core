/// The browser entry selects a portal; the authenticated backend role grants access.
enum PortalAudience {
  kitchen('cocina', 'business', '/cocina/', 'Cocina'),
  administration(
    'administracion',
    'admin',
    '/administracion/',
    'Administración',
  );

  const PortalAudience(
    this.configurationValue,
    this.role,
    this.entryPath,
    this.label,
  );
  final String configurationValue, role, entryPath, label;

  bool accepts(String role) => role == this.role;
  String get loginTitle => 'Acceso a $label';
  String get applicationTitle => 'SnackUP · $label';
  String get subtitle => switch (this) {
    kitchen => 'Cafetería universitaria · Operación del local',
    administration => 'Cafetería universitaria · Gestión institucional',
  };
  String get accessNotice => switch (this) {
    kitchen => 'Este acceso es exclusivo para las cuentas de Cocina.',
    administration =>
      'Este acceso es exclusivo para las cuentas de Administración.',
  };
  String get help => switch (this) {
    kitchen =>
      'Ingresa con la cuenta autorizada de tu local. Si todavía no tienes acceso, solicita una cuenta al responsable del servicio.',
    administration =>
      'Ingresa con tu cuenta administrativa autorizada. Si necesitas acceso, solicítalo al responsable del servicio.',
  };

  static PortalAudience? fromUri(Uri uri) {
    final hostLabel = uri.host.toLowerCase().split('.').first;
    for (final audience in values) {
      if (hostLabel == audience.configurationValue) return audience;
    }
    for (final audience in values) {
      if (uri.path ==
              audience.entryPath.substring(0, audience.entryPath.length - 1) ||
          uri.path.startsWith(audience.entryPath)) {
        return audience;
      }
    }
    return null;
  }

  static PortalAudience? forLocation(Uri uri, {String configured = ''}) {
    final actual = fromUri(uri);
    if (configured.isEmpty) return actual;
    final matches = values.where(
      (audience) => audience.configurationValue == configured,
    );
    if (matches.length != 1 || (actual != null && matches.single != actual)) {
      throw ArgumentError('The portal configuration does not match this URL.');
    }
    return matches.single;
  }

  bool acceptsApiBase(Uri location, Uri api) =>
      location.origin == api.origin && api.path == '/api/legacy/v1/';
}
