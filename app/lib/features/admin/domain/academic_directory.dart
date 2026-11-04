import '../../../api/api_client.dart';
import '../../../operations/models.dart';
import '../../../operations/portal_configuration.dart';
import 'admin_models.dart';

class AcademicEntry {
  const AcademicEntry({
    required this.id,
    required this.name,
    required this.kind,
    this.careerId,
  });
  final String id, name, kind;
  final String? careerId;
  factory AcademicEntry.fromJson(dynamic value) {
    final d = object(value), kind = requiredText(object(value), 'kind');
    if (!['career', 'group'].contains(kind)) {
      throw const ApiException(
        'Catálogo académico no válido.',
        code: 'INVALID_RESPONSE',
      );
    }
    return AcademicEntry(
      id: requiredText(d, 'id'),
      name: requiredText(d, 'name'),
      kind: kind,
      careerId: kind == 'group' ? requiredText(d, 'careerId') : null,
    );
  }
}

class AcademicDirectory {
  AcademicDirectory(Iterable<AcademicEntry> entries)
    : entries = List.unmodifiable(entries) {
    final ids = this.entries.map((e) => e.id).toSet();
    final careers = this.entries
        .where((e) => e.kind == 'career')
        .map((e) => e.id)
        .toSet();
    if (ids.length != this.entries.length ||
        this.entries.any(
          (e) => e.kind == 'group' && !careers.contains(e.careerId),
        )) {
      throw const ApiException(
        'El catálogo académico tiene referencias incompletas.',
        code: 'INVALID_RESPONSE',
      );
    }
  }
  final List<AcademicEntry> entries;
  Map<String, String> get careers =>
      _options(entries.where((e) => e.kind == 'career'));
  Map<String, String> groups(String? careerId) => _options(
    entries.where((e) => e.kind == 'group' && e.careerId == careerId),
  );
  String? name(String? id) {
    for (final e in entries) {
      if (e.id == id) return e.name;
    }
    return null;
  }

  static Map<String, String> _options(Iterable<AcademicEntry> source) {
    final sorted = source.toList()..sort((a, b) => a.name.compareTo(b.name));
    return {for (final e in sorted) e.id: e.name};
  }

  /// Compatibility for the separate legacy Firebase/demo application.
  factory AcademicDirectory.fromReviews(Iterable<AdminReview> reviews) {
    final entries = <String, AcademicEntry>{};
    for (final r in reviews) {
      final c = r.careerId ?? 'career:${r.career}';
      final g = r.groupId ?? 'group:$c:${r.group}';
      entries[c] = AcademicEntry(id: c, name: r.career, kind: 'career');
      entries[g] = AcademicEntry(
        id: g,
        name: r.group,
        kind: 'group',
        careerId: c,
      );
    }
    return AcademicDirectory(entries.values);
  }
}

class AdminReferenceData {
  const AdminReferenceData(this.configuration, this.academics);
  final PortalConfiguration configuration;
  final AcademicDirectory academics;
}

abstract class AdminReferenceSource {
  Future<AdminReferenceData> loadReferences();
}
