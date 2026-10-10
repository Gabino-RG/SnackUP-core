import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SnackAccount {
  const SnackAccount({
    required this.uid,
    this.email = '',
    this.displayName = '',
  });
  final String uid;
  final String email;
  final String displayName;
}

class StudentProfileInput {
  const StudentProfileInput({
    required this.name,
    required this.controlNumber,
    required this.acceptedTerms,
  });
  final String name;
  final String controlNumber;
  final bool acceptedTerms;
  void validate() {
    if (name.trim().length > 120 ||
        name.trim().split(RegExp(r'\s+')).length < 2) {
      throw const AuthActionException(
        'Escribe tu nombre y apellido (máximo 120 caracteres).',
      );
    }
    if (!RegExp(r'^\d{8,20}$').hasMatch(controlNumber.trim())) {
      throw const AuthActionException(
        'El número de control debe contener entre 8 y 20 dígitos.',
      );
    }
    if (!acceptedTerms) {
      throw const AuthActionException(
        'Acepta el aviso de privacidad para continuar.',
      );
    }
  }
}

class AuthActionException implements Exception {
  const AuthActionException(this.message);
  final String message;
}

String normalizeAuthEmail(String email) => email.trim().toLowerCase();
bool isStudentEmail(String email) =>
    RegExp(r'^[^\s@]+@utsjr\.edu\.mx$').hasMatch(normalizeAuthEmail(email));
// Claim equality intentionally rejects "true", 1 and editable profile fields.
bool hasAdministrativeClaim(Map<String, dynamic> claims) =>
    claims['admin'] == true;

enum SnackRole { student, business, incomplete, unsupported }

SnackRole profileRole(Map<String, dynamic>? profile) {
  if (profile == null) return SnackRole.incomplete;
  return switch (profile['role']) {
    'user' => SnackRole.student,
    'business' => SnackRole.business,
    _ => SnackRole.unsupported,
  };
}

Map<String, dynamic> studentProfilePayload({
  required String email,
  required StudentProfileInput input,
  required Object serverTimestamp,
}) {
  input.validate();
  if (!isStudentEmail(email)) {
    throw const AuthActionException(
      'Usa tu correo institucional @utsjr.edu.mx.',
    );
  }
  return {
    'role': 'user',
    'email': normalizeAuthEmail(email),
    'displayName': input.name.trim(),
    'numeroDeControl': input.controlNumber.trim(),
    'createdAt': serverTimestamp,
    'privacyAcceptedAt': serverTimestamp,
    'privacyVersion': '2',
  };
}

abstract class SnackAuthRepository {
  SnackAccount? get currentAccount;
  Stream<SnackAccount?> watchAccount();
  Future<Map<String, dynamic>> loadClaims(String uid);
  Stream<Map<String, dynamic>?> watchProfile(String uid);
  Future<bool> ownsBusiness(String uid);
  Future<void> signIn(String email, String password);
  Future<void> sendPasswordReset(String email);
  Future<void> registerStudent(
    String email,
    String password,
    StudentProfileInput input,
  );
  Future<void> completeStudentProfile(StudentProfileInput input);
  Future<void> signOut();
}

class FirebaseSnackAuthRepository implements SnackAuthRepository {
  FirebaseSnackAuthRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  SnackAccount? _account(User? user) => user == null
      ? null
      : SnackAccount(
          uid: user.uid,
          email: user.email ?? '',
          displayName: user.displayName ?? '',
        );
  @override
  SnackAccount? get currentAccount => _account(_auth.currentUser);
  @override
  Stream<SnackAccount?> watchAccount() => _auth.idTokenChanges().map(_account);
  @override
  Future<Map<String, dynamic>> loadClaims(String uid) async {
    final user = _auth.currentUser;
    if (user == null || user.uid != uid) {
      throw const AuthActionException(
        'La sesión cambió. Vuelve a iniciar sesión.',
      );
    }
    return (await user.getIdTokenResult()).claims ?? {};
  }

  @override
  Stream<Map<String, dynamic>?> watchProfile(String uid) =>
      _db.collection('users').doc(uid).snapshots().map((doc) => doc.data());
  @override
  Future<bool> ownsBusiness(String uid) async =>
      (await _db
              .collection('businesses')
              .where('ownerId', isEqualTo: uid)
              .limit(1)
              .get(const GetOptions(source: Source.server)))
          .docs
          .isNotEmpty;
  @override
  Future<void> signIn(String email, String password) async {
    // Password whitespace is significant and is never normalized.
    await _auth.signInWithEmailAndPassword(
      email: normalizeAuthEmail(email),
      password: password,
    );
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    if (!RegExp(
      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
    ).hasMatch(normalizeAuthEmail(email))) {
      throw const AuthActionException(
        'Escribe un correo válido en el campo de correo.',
      );
    }
    try {
      await _auth.sendPasswordResetEmail(email: normalizeAuthEmail(email));
    } on FirebaseAuthException catch (error) {
      if (error.code != 'user-not-found') rethrow;
    }
  }

  @override
  Future<void> registerStudent(
    String email,
    String password,
    StudentProfileInput input,
  ) async {
    input.validate();
    final normalized = normalizeAuthEmail(email);
    if (!isStudentEmail(normalized)) {
      throw const AuthActionException(
        'Usa tu correo institucional @utsjr.edu.mx.',
      );
    }
    if (password.length < 6) {
      throw const AuthActionException(
        'La contraseña debe tener al menos 6 caracteres.',
      );
    }
    final current = _auth.currentUser;
    if (current == null) {
      await _auth.createUserWithEmailAndPassword(
        email: normalized,
        password: password,
      );
    } else if (normalizeAuthEmail(current.email ?? '') != normalized) {
      throw const AuthActionException(
        'Ya hay otra sesión abierta. Ciérrala antes de crear una cuenta.',
      );
    }
    // Auth and Firestore cannot be committed together. Keep the account signed in
    // on failure so the exact same account can retry profile completion.
    try {
      await completeStudentProfile(input);
    } catch (error) {
      if (error is AuthActionException) rethrow;
      throw const AuthActionException(
        'Tu cuenta ya existe, pero falta guardar el perfil. Reintenta para completar el registro con esta misma cuenta.',
      );
    }
  }

  @override
  Future<void> completeStudentProfile(StudentProfileInput input) async {
    input.validate();
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthActionException(
        'Inicia sesión para completar tu perfil.',
      );
    }
    if (!isStudentEmail(user.email ?? '')) {
      throw const AuthActionException(
        'Esta cuenta requiere que administración habilite su acceso.',
      );
    }
    final ref = _db.collection('users').doc(user.uid);
    final savedName = await _db.runTransaction<String>((transaction) async {
      final existing = await transaction.get(ref);
      if (existing.exists) {
        if (profileRole(existing.data()) != SnackRole.student) {
          throw const AuthActionException(
            'El perfil existente requiere revisión de administración.',
          );
        }
        // Completion is create-only; never overwrite roles or user data.
        final existingName = existing.data()?['displayName'];
        return existingName is String ? existingName : '';
      }
      transaction.set(
        ref,
        studentProfilePayload(
          email: user.email ?? '',
          input: input,
          serverTimestamp: FieldValue.serverTimestamp(),
        ),
      );
      return input.name.trim();
    });
    // Firestore is the authoritative profile. A cosmetic Auth display-name
    // update must not turn a successfully created profile into a failed signup.
    try {
      if (savedName.isNotEmpty) await user.updateDisplayName(savedName);
    } on FirebaseAuthException catch (_) {
      /* Profile remains available. */
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();
}

String authErrorMessage(Object error) {
  if (error is AuthActionException) return error.message;
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' => 'Correo o contraseña incorrectos.',
      'invalid-email' => 'Escribe un correo válido.',
      'email-already-in-use' =>
        'Este correo ya tiene una cuenta. Inicia sesión o recupera tu contraseña.',
      'weak-password' => 'La contraseña debe tener al menos 6 caracteres.',
      'network-request-failed' =>
        'Sin conexión. Revisa tu red y vuelve a intentar.',
      'too-many-requests' =>
        'Hubo demasiados intentos. Espera unos minutos y vuelve a intentar.',
      'user-disabled' =>
        'La cuenta está deshabilitada. Contacta a administración.',
      _ => 'No se pudo completar la solicitud. Vuelve a intentar.',
    };
  }
  return 'No se pudo completar la solicitud. Revisa tu conexión y vuelve a intentar.';
}
