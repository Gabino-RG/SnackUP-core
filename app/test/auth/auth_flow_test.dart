import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snackup/features/auth/auth_gate.dart';
import 'package:snackup/features/auth/auth_repository.dart';
import 'package:snackup/features/auth/login_screen.dart';
import 'package:snackup/features/auth/business_login_screen.dart';

class FakeAuthRepository implements SnackAuthRepository {
  SnackAccount? account;
  Map<String, dynamic>? profile;
  Map<String, dynamic> claims = {};
  bool businessOwned = false, claimsFail = false;
  int claimReads = 0, signInCalls = 0, signOutCalls = 0;
  String? receivedPassword, resetEmail;
  Completer<void>? loginRequest;
  final accounts = StreamController<SnackAccount?>.broadcast();
  final profiles = StreamController<Map<String, dynamic>?>.broadcast();
  @override
  SnackAccount? get currentAccount => account;
  @override
  Stream<SnackAccount?> watchAccount() async* {
    yield account;
    yield* accounts.stream;
  }

  @override
  Future<Map<String, dynamic>> loadClaims(String uid) async {
    claimReads++;
    if (claimsFail) throw StateError('network');
    return claims;
  }

  @override
  Stream<Map<String, dynamic>?> watchProfile(String uid) async* {
    yield profile;
    yield* profiles.stream;
  }

  @override
  Future<bool> ownsBusiness(String uid) async => businessOwned;
  @override
  Future<void> signIn(String email, String password) async {
    signInCalls++;
    receivedPassword = password;
    await loginRequest?.future;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    resetEmail = email;
  }

  @override
  Future<void> registerStudent(
    String email,
    String password,
    StudentProfileInput input,
  ) async {
    input.validate();
  }

  @override
  Future<void> completeStudentProfile(StudentProfileInput input) async {
    input.validate();
    profile = {'role': 'user'};
    profiles.add(profile);
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    account = null;
    accounts.add(null);
  }

  Future<void> close() async {
    await accounts.close();
    await profiles.close();
  }
}

const student = SnackAccount(uid: 's1', email: 'alumno@utsjr.edu.mx');
Widget gate(FakeAuthRepository repository, {WidgetBuilder? studentBuilder}) =>
    MaterialApp(
      home: AuthWrapper(
        repository: repository,
        studentBuilder:
            studentBuilder ?? (_) => const Scaffold(body: Text('STUDENT HOME')),
        businessBuilder: (_) => const Scaffold(body: Text('BUSINESS HOME')),
        adminBuilder: (_) => const Scaffold(body: Text('ADMIN HOME')),
      ),
    );
void main() {
  test(
    'public profile payload is student-only, records acceptance and normalizes identity',
    () {
      final marker = Object();
      final payload = studentProfilePayload(
        email: ' Alumno@UTSJR.EDU.MX ',
        input: const StudentProfileInput(
          name: '  Alumno Uno  ',
          controlNumber: ' 202314096 ',
          acceptedTerms: true,
        ),
        serverTimestamp: marker,
      );
      expect(payload['role'], 'user');
      expect(payload['email'], 'alumno@utsjr.edu.mx');
      expect(payload['displayName'], 'Alumno Uno');
      expect(payload['numeroDeControl'], '202314096');
      expect(payload['privacyAcceptedAt'], same(marker));
      expect(payload['privacyVersion'], '2');
      expect(payload.containsKey('admin'), false);
      expect(
        () => studentProfilePayload(
          email: 'x@utsjr.edu.mx',
          input: const StudentProfileInput(
            name: 'Alumno Uno',
            controlNumber: '202314096',
            acceptedTerms: false,
          ),
          serverTimestamp: marker,
        ),
        throwsA(isA<AuthActionException>()),
      );
      expect(
        () => studentProfilePayload(
          email: 'x@example.com',
          input: const StudentProfileInput(
            name: 'Alumno Uno',
            controlNumber: '202314096',
            acceptedTerms: true,
          ),
          serverTimestamp: marker,
        ),
        throwsA(isA<AuthActionException>()),
      );
    },
  );
  test(
    'claims and profile roles fail closed for malformed/self-assigned admin values',
    () {
      for (final value in ['true', 1, false, null]) {
        expect(hasAdministrativeClaim({'admin': value}), false);
      }
      expect(hasAdministrativeClaim({'admin': true}), true);
      expect(
        profileRole({'role': 'admin', 'admin': true}),
        SnackRole.unsupported,
      );
      expect(profileRole({'role': 123}), SnackRole.unsupported);
      expect(profileRole(null), SnackRole.incomplete);
    },
  );
  testWidgets(
    'registration account waits for profile instead of signing out, then enters student home',
    (tester) async {
      final repo = FakeAuthRepository()..account = student;
      addTearDown(repo.close);
      await tester.pumpWidget(gate(repo));
      await tester.pumpAndSettle();
      expect(find.text('Completa tu registro'), findsOneWidget);
      expect(repo.signOutCalls, 0);
      repo.profile = {'role': 'user'};
      repo.profiles.add(repo.profile);
      await tester.pumpAndSettle();
      expect(find.text('STUDENT HOME'), findsOneWidget);
      expect(repo.signOutCalls, 0);
      expect(repo.claimReads, 1);
    },
  );
  testWidgets(
    'boolean admin claim grants admin route without student profile',
    (tester) async {
      final repo = FakeAuthRepository()
        ..account = student
        ..claims = {'admin': true};
      addTearDown(repo.close);
      await tester.pumpWidget(gate(repo));
      await tester.pumpAndSettle();
      expect(find.text('ADMIN HOME'), findsOneWidget);
      expect(find.text('Completa tu registro'), findsNothing);
    },
  );
  testWidgets('profile role admin never grants administration', (tester) async {
    final repo = FakeAuthRepository()
      ..account = student
      ..profile = {'role': 'admin', 'admin': true};
    addTearDown(repo.close);
    await tester.pumpWidget(gate(repo));
    await tester.pumpAndSettle();
    expect(find.text('ADMIN HOME'), findsNothing);
    expect(
      find.textContaining('no tiene un acceso habilitado'),
      findsOneWidget,
    );
  });
  testWidgets('business role requires an assigned business and retry works', (
    tester,
  ) async {
    final repo = FakeAuthRepository()
      ..account = student
      ..profile = {'role': 'business'};
    addTearDown(repo.close);
    await tester.pumpWidget(gate(repo));
    await tester.pumpAndSettle();
    expect(find.text('BUSINESS HOME'), findsNothing);
    expect(find.textContaining('no tiene un local asignado'), findsOneWidget);
    repo.businessOwned = true;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('BUSINESS HOME'), findsOneWidget);
  });
  testWidgets('claim failure is retryable without discarding account', (
    tester,
  ) async {
    final repo = FakeAuthRepository()
      ..account = student
      ..profile = {'role': 'user'}
      ..claimsFail = true;
    addTearDown(repo.close);
    await tester.pumpWidget(gate(repo));
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudo verificar'), findsOneWidget);
    expect(repo.signOutCalls, 0);
    repo.claimsFail = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('STUDENT HOME'), findsOneWidget);
    expect(repo.claimReads, 2);
  });
  testWidgets('signout removes protected routes above the root', (
    tester,
  ) async {
    final repo = FakeAuthRepository()
      ..account = student
      ..profile = {'role': 'user'};
    addTearDown(repo.close);
    await tester.pumpWidget(
      gate(
        repo,
        studentBuilder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('PRIVATE DETAIL')),
              ),
            ),
            child: const Text('Open detail'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open detail'));
    await tester.pumpAndSettle();
    expect(find.text('PRIVATE DETAIL'), findsOneWidget);
    await repo.signOut();
    await tester.pumpAndSettle();
    expect(find.text('PRIVATE DETAIL'), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
  testWidgets('claim revocation removes an already open protected dialog', (
    tester,
  ) async {
    final repo = FakeAuthRepository()
      ..account = student
      ..claims = {'admin': true}
      ..profile = {'role': 'user'};
    addTearDown(repo.close);
    await tester.pumpWidget(
      MaterialApp(
        home: AuthWrapper(
          repository: repo,
          studentBuilder: (_) => const Scaffold(body: Text('STUDENT HOME')),
          adminBuilder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    const AlertDialog(content: Text('ADMIN PRIVATE DETAIL')),
              ),
              child: const Text('Open admin detail'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open admin detail'));
    await tester.pumpAndSettle();
    expect(find.text('ADMIN PRIVATE DETAIL'), findsOneWidget);
    repo.claims = {};
    repo.account = SnackAccount(uid: student.uid, email: student.email);
    repo.accounts.add(repo.account);
    await tester.pumpAndSettle();
    expect(find.text('ADMIN PRIVATE DETAIL'), findsNothing);
    expect(find.text('STUDENT HOME'), findsOneWidget);
  });
  testWidgets(
    'login preserves password spaces, blocks concurrent submissions and survives disposal',
    (tester) async {
      final request = Completer<void>();
      final repo = FakeAuthRepository()..loginRequest = request;
      addTearDown(repo.close);
      await tester.pumpWidget(MaterialApp(home: LoginScreen(repository: repo)));
      await tester.enterText(find.byType(TextField).at(0), 'admin@example.com');
      await tester.enterText(
        find.byType(TextField).at(1),
        ' pass with spaces ',
      );
      final password = tester.widget<TextField>(find.byType(TextField).at(1));
      password.onSubmitted!('ignored');
      password.onSubmitted!('ignored');
      await tester.pump();
      expect(repo.signInCalls, 1);
      expect(repo.receivedPassword, ' pass with spaces ');
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      request.completeError(StateError('network'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'business login returns to gate, never directly pushes business home',
    (tester) async {
      final repo = FakeAuthRepository();
      addTearDown(repo.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => BusinessLoginScreen(repository: repo),
                  ),
                ),
                child: const Text('Root gate'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Root gate'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(0),
        'student@utsjr.edu.mx',
      );
      await tester.enterText(find.byType(TextField).at(1), ' password ');
      tester.widget<TextField>(find.byType(TextField).at(1)).onSubmitted!(
        'ignored',
      );
      await tester.pumpAndSettle();
      expect(find.text('Root gate'), findsOneWidget);
      expect(find.byType(BusinessLoginScreen), findsNothing);
      expect(repo.receivedPassword, ' password ');
    },
  );
  testWidgets('password recovery is actionable from login', (tester) async {
    final repo = FakeAuthRepository();
    addTearDown(repo.close);
    await tester.pumpWidget(MaterialApp(home: LoginScreen(repository: repo)));
    await tester.enterText(find.byType(TextField).first, 'alumno@utsjr.edu.mx');
    await tester.ensureVisible(find.text('¿Olvidaste tu contraseña?'));
    await tester.tap(find.text('¿Olvidaste tu contraseña?'));
    await tester.pump();
    expect(repo.resetEmail, 'alumno@utsjr.edu.mx');
    expect(
      find.textContaining('Si el correo tiene una cuenta'),
      findsOneWidget,
    );
  });
}
