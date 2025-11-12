import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'firebase_options.dart'; // powstaje po flutterfire configure
import 'game.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const COPeduApp());
}

class COPeduApp extends StatelessWidget {
  const COPeduApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'COPedu',
      theme: ThemeData(
        useMaterial3: true,
        // Zamiast colorSchemeSeed użyjemy jawnego ColorScheme
        colorScheme: const ColorScheme.light(
          primary: Colors.blueAccent,   // zostaje róż jako kolor akcentu
          secondary: Colors.blueAccent,
          surface: Colors.white,        // ← białe powierzchnie
          background: Colors.white,     // ← białe tło
        ),
        scaffoldBackgroundColor: Colors.white, // białe tło Scaffolda
        canvasColor: Colors.white,             // białe tło np. list/scrolli
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          surfaceTintColor: Colors.transparent, // wyłącza różowy „nalot”
        ),
        cardTheme: const CardTheme(
          color: Colors.white,
          surfaceTintColor: Colors.transparent, // bez tintu na kartach
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.white,        // dół też na biało
          // (opcjonalnie) indicatorColor: Colors.transparent,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

/// Bramka logowania → po zalogowaniu zakłada dokument użytkownika w Firestore
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<void> _ensureUserDoc(User u) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(u.uid);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        final displayName =
            u.displayName ?? (u.email?.split('@').first ?? 'Uczestnik');
        tx.set(ref, {
          'displayName': displayName,
          'role': 'user', // domyślnie user; w konsoli można zmienić na exhibitor/admin
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snap.data;
        if (user == null) return const LoginPage();
        // upewnij się, że mamy dokument użytkownika
        _ensureUserDoc(user);
        return HomeShell(user: user);
      },
    );
  }
}

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.user});
  final User user;

  @override
  Widget build(BuildContext context) {
    final userDocStream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDocStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting || !snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snap.data!.data() ?? {};
        final role = (data['role'] as String?) ?? 'user';
        final displayName = (data['displayName'] as String?) ?? 'Uczestnik';
        final company = (data['company'] as String?)?.trim();

        // Strony i zakładki
        final pages = <Widget>[];
        final destinations = <NavigationDestination>[];

        // Dodaj GamePage
        pages.add(GamePage(currentUserId: user.uid));
        destinations.add(const NavigationDestination(
          icon: Icon(Icons.videogame_asset),
          label: 'Gra',
        ));

        // USER: Skaner
        if (role == 'user') {
          pages.add(ScanPage(currentUserId: user.uid));
          destinations.add(const NavigationDestination(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Skanuj',
          ));
        }

        // EXHIBITOR/ADMIN: Mój QR
        if (role == 'exhibitor' || role == 'admin') {
          final exhibitorLabel =
          (role == 'exhibitor' && company != null && company.isNotEmpty)
              ? company
              : displayName;

          pages.add(ExhibitorQrPage(
            exhibitorId: user.uid,
            exhibitorName: exhibitorLabel,
          ));
          destinations.add(const NavigationDestination(
            icon: Icon(Icons.badge_outlined),
            label: 'Mój QR',
          ));
        }

        // ADMIN: Użytkownicy (panel zarządzania)
        if (role == 'admin') {
          pages.add(AdminUsersPage(currentUserId: user.uid));
          destinations.add(const NavigationDestination(
            icon: Icon(Icons.people_alt_outlined),
            label: 'Użytkownicy',
          ));
        }

        // NOWA: Wystawcy (dla wszystkich) — przed Rankingiem
        pages.add(const ExhibitorsPage());
        destinations.add(const NavigationDestination(
          icon: Icon(Icons.storefront_outlined),
          label: 'Wystawcy',
        ));

        // Ranking – zawsze (admin widzi pełne dane)
        if (role == 'admin') {
          pages.add(AdminLeaderboardPage(currentUserId: user.uid));
        } else {
          pages.add(LeaderboardPage(
            currentUserId: user.uid,
            currentUserRole: role, // 'user' lub 'exhibitor'
          ));
        }
        destinations.add(const NavigationDestination(
          icon: Icon(Icons.leaderboard_outlined),
          label: 'Ranking',
        ));

        // Fallback (raczej nie nastąpi, bo mamy już min. 2 zakładki)
        if (pages.isEmpty) {
          pages.add(Center(
            child: Text('Brak uprawnień do wyświetlenia zawartości dla roli: $role'),
          ));
          destinations.add(const NavigationDestination(
            icon: Icon(Icons.info_outline),
            label: 'Info',
          ));
        }

        return _HomeScaffold(
          pages: pages,
          destinations: destinations,
          title: 'Clinical Optometry Poland 2025',
        );
      },
    );
  }
}



/// Prostą klasę, by nie mieszać stanu z rolami
class _HomeScaffold extends StatefulWidget {
  const _HomeScaffold({
    required this.pages,
    required this.destinations,
    required this.title,
  });

  final List<Widget> pages;
  final List<NavigationDestination> destinations;
  final String title;

  @override
  State<_HomeScaffold> createState() => _HomeScaffoldState();
}

class _HomeScaffoldState extends State<_HomeScaffold> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pageCount = widget.pages.length;
    final hasNav = widget.destinations.length >= 2 && pageCount >= 2;

    // Upewnij się, że indeks nie wychodzi poza zakres (np. po zmianie ról)
    if (_currentIndex >= pageCount) {
      _currentIndex = 0;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Wyloguj',
            onPressed: () async => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: widget.pages[_currentIndex],
      bottomNavigationBar: hasNav
          ? NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: widget.destinations,
      )
          : null, // ← gdy 1 zakładka, nie pokazujemy NavigationBar
    );
  }
}

class _LoginBrand extends StatelessWidget {
  const _LoginBrand();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/cop_logo.png',
          width: 160,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 12),
        const Text(
          'Zaloguj się',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}


class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false;
  String? error;

  bool rememberMe = true;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() {
      rememberMe = _prefs?.getBool('remember_me') ?? true;
    });
  }

  Future<void> _saveRememberMe(bool value) async {
    setState(() => rememberMe = value);
    await _prefs?.setBool('remember_me', value);
  }

  Future<void> _applyPersistence() async {
    // Na Android/iOS i tak jest trwałe. Na Web ustawiamy zgodnie z checkboxem.
    if (kIsWeb) {
      try {
        await FirebaseAuth.instance.setPersistence(
          rememberMe ? Persistence.LOCAL : Persistence.SESSION,
        );
      } catch (_) {/* nic – na mobile nie jest potrzebne */}
    }
  }

  Future<void> signIn() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await _applyPersistence();
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.text.trim(),
        password: password.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(() => error = '${e.code}: ${e.message}');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _LoginBrand(),
                const SizedBox(height: 16),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Hasło',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: rememberMe,
                  onChanged: (v) => _saveRememberMe(v ?? true),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Zapamiętaj mnie'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: loading ? null : signIn,
                        child: loading
                            ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Zaloguj'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      // ← zamiast tworzyć konto tu, przechodzimy do osobnego ekranu rejestracji
                      child: OutlinedButton(
                        onPressed: loading
                            ? null
                            : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const RegisterPage()),
                          );
                        },
                        child: const Text('Zarejestruj'),
                      ),
                    ),
                  ],
                ),
                /* ⬇⬇⬇ DODAJ TO PONIŻEJ ⬇⬇⬇ */
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: loading
                      ? null
                      : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DeleteAccountPage()),
                    );
                  },
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Usuń konto'),
                  style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                ),
/* ⬆⬆⬆ KONIEC DODATKU ⬆⬆⬆ */
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ⬇⬇⬇ REGISTER PAGE ⬇⬇⬇
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final company = TextEditingController(); // opcjonalne
  final password = TextEditingController();
  final confirm = TextEditingController();

  bool loading = false;
  String? error;

  @override
  void dispose() {
    firstName.dispose();
    lastName.dispose();
    email.dispose();
    phone.dispose();
    company.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  bool _validate() {
    if (firstName.text.trim().isEmpty) {
      error = 'Podaj imię.';
      return false;
    }
    if (lastName.text.trim().isEmpty) {
      error = 'Podaj nazwisko.';
      return false;
    }
    if (!email.text.contains('@')) {
      error = 'Podaj poprawny e-mail.';
      return false;
    }
    if (phone.text.trim().isEmpty) {
      error = 'Podaj numer telefonu.';
      return false;
    }
    if (password.text.length < 6) {
      error = 'Hasło musi mieć co najmniej 6 znaków.';
      return false;
    }
    if (password.text != confirm.text) {
      error = 'Hasła nie są takie same.';
      return false;
    }
    return true;
  }

  Future<void> _register() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (!_validate()) {
        setState(() {});
        return;
      }

      // 1) Tworzymy konto w Auth
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.text.trim(),
        password: password.text,
      );

      final user = cred.user!;
      final displayName = '${firstName.text.trim()} ${lastName.text.trim()}';
      await user.updateDisplayName(displayName);

      // 2) Zapisujemy profil w Firestore (role domyślnie 'user')
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'displayName': displayName,
        'firstName': firstName.text.trim(),
        'lastName': lastName.text.trim(),
        'email': email.text.trim(),
        'phone': phone.text.trim(),
        'company': company.text.trim().isEmpty ? null : company.text.trim(),
        'role': 'user',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) Navigator.of(context).pop(); // wracamy do aplikacji zalogowani
    } on FirebaseAuthException catch (e) {
      setState(() => error = '${e.code}: ${e.message}');
    } catch (e) {
      setState(() => error = 'Nie udało się zarejestrować: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rejestracja')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: firstName,
                        decoration: const InputDecoration(
                          labelText: 'Imię *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: lastName,
                        decoration: const InputDecoration(
                          labelText: 'Nazwisko *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Numer telefonu *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: company,
                  decoration: const InputDecoration(
                    labelText: 'Nazwa firmy (opcjonalnie)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Hasło *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Powtórz hasło *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: loading ? null : _register,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: loading
                        ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Utwórz konto'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false;
  String? error;
  bool consent = false;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _deleteBatch(Query<Map<String, dynamic>> baseQuery, {int batchSize = 300}) async {
    final db = FirebaseFirestore.instance;
    while (true) {
      final snap = await baseQuery.limit(batchSize).get();
      if (snap.docs.isEmpty) break;
      final batch = db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      if (snap.docs.length < batchSize) break;
    }
  }

  Future<void> _deleteUserData(String uid) async {
    final db = FirebaseFirestore.instance;

    // users/{uid}
    try { await db.collection('users').doc(uid).delete(); } catch (_) {}

    // scans: wszystkie, które należą do użytkownika jako "userId"
    await _deleteBatch(db.collection('scans').where('userId', isEqualTo: uid));

    // user_exhibitor_points: pary user–exhibitor
    await _deleteBatch(db.collection('user_exhibitor_points').where('userId', isEqualTo: uid));

    // game_scores: wyniki gry
    await _deleteBatch(db.collection('game_scores').where('userId', isEqualTo: uid));
  }

  Future<void> _onDelete() async {
    setState(() { loading = true; error = null; });

    try {
      final mail = email.text.trim();
      final pass = password.text;

      if (!mail.contains('@') || pass.isEmpty) {
        setState(() => error = 'Podaj poprawny e-mail i hasło.');
        return;
      }
      if (!consent) {
        setState(() => error = 'Zaznacz potwierdzenie usunięcia konta.');
        return;
      }

      // 1) Zaloguj (jeśli nie zalogowany) – to daje „recent login”
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: mail, password: pass);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => error = 'Nie udało się uwierzytelnić użytkownika.');
        return;
      }

      // 2) (opcjonalnie) dodatkowy reauth — bywa wymagany na iOS/Web
      final cred = EmailAuthProvider.credential(email: mail, password: pass);
      await user.reauthenticateWithCredential(cred);

      // 3) Potwierdzenie
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Usunąć konto?'),
          content: const Text(
            'Tej operacji nie można cofnąć. Zostaną usunięte dane profilu '
                'i powiązane wpisy (punkty, skany, wyniki gry).',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Usuń')),
          ],
        ),
      );
      if (ok != true) return;

      // 4) Sprzątanie w Firestore
      await _deleteUserData(user.uid);

      // 5) Usunięcie konta z Auth
      await user.delete();

      // 6) Wyloguj i wróć do ekranu startowego
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      _snack('Konto zostało usunięte.');
      Navigator.of(context).popUntil((r) => r.isFirst);

    } on FirebaseAuthException catch (e) {
      setState(() => error = '${e.code}: ${e.message}');
    } catch (e) {
      setState(() => error = 'Błąd: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Usuń konto')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Aby usunąć konto, podaj e-mail i hasło do logowania.',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Hasło',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: consent,
                  onChanged: (v) => setState(() => consent = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Rozumiem, że to działanie jest nieodwracalne.'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: loading ? null : _onDelete,
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Usuń konto na zawsze'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
/// --- SKANER QR ---
/// Skanuje kody w formacie: EXHIBITOR:<exhibitorId>
/// Po zeskanowaniu przyznaje 1 punkt użytkownikowi (1x na wystawcę)
class ScanPage extends StatefulWidget {
  const ScanPage({super.key, required this.currentUserId});
  final String currentUserId;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool _processing = false;
  String? _last;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _awardPoint(String exhibitorId) async {
    final db = FirebaseFirestore.instance;
    final uid = widget.currentUserId;

    // ✦ DODANE: tylko rola 'user' może zbierać punkty
    try {
      final meSnap = await db.collection('users').doc(uid).get();
      final myRole = (meSnap.data()?['role'] as String?) ?? 'user';
      if (myRole != 'user') {
        _snack('Konta wystawcy/admina nie zbierają punktów.');
        return;
      }
    } catch (_) {
      _snack('Nie udało się odczytać Twojej roli.');
      return;
    }

    // 0) Nie pozwalaj skanować własnego kodu
    if (uid == exhibitorId) {
      _snack('Nie możesz skanować własnego kodu 🙂');
      return;
    }

    // 1) Sprawdź, czy to na pewno kod wystawcy (lub admina)
    try {
      final exSnap = await db.collection('users').doc(exhibitorId).get();
      final exRole = (exSnap.data()?['role'] as String?) ?? '';
      if (exRole != 'exhibitor' && exRole != 'admin') {
        _snack('To nie jest kod wystawcy.');
        return;
      }
    } catch (_) {
      _snack('Błąd weryfikacji kodu.');
      return;
    }

    // 2) Jednorazowy punkt per (user, exhibitor) – klucz łączony
    final key = '${uid}_$exhibitorId';

    try {
      await db.runTransaction((tx) async {
        final ref = db.collection('user_exhibitor_points').doc(key);
        final snap = await tx.get(ref);
        if (snap.exists) {
          throw 'already';
        }

        // Flaga: już przyznane (blokuje kolejne próby dla tej pary)
        tx.set(ref, {
          'userId': uid,
          'exhibitorId': exhibitorId,
          'awarded': true,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Wpis do rankingu (scans) – tylko przy pierwszym razie
        final scansRef = db.collection('scans').doc();
        tx.set(scansRef, {
          'userId': uid,
          'exhibitorId': exhibitorId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      _snack('Punkt przyznany 🎉');
    } catch (e) {
      _snack(
        (e == 'already')
            ? 'Ten wystawca przydzielił Ci już punkt. Aby zdobywać kolejne punkty, podejdź do innego wystawcy.'
            : 'Błąd przyznawania punktu. Spróbuj ponownie za chwilę.',
      );
    }
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_processing) return;

    final code =
    capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (code == null || code == _last) return;

    if (code.startsWith('EXHIBITOR:')) {
      _processing = true;
      setState(() => _last = code);

      final exhibitorId = code.substring('EXHIBITOR:'.length);
      await _awardPoint(exhibitorId);

      // krótki cooldown, by uniknąć wielokrotnego wywołania
      await Future.delayed(const Duration(milliseconds: 600));
      _processing = false;
    } else {
      _snack('Nieprawidłowy kod QR.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const ListTile(
          leading: Icon(Icons.qr_code_scanner),
          title: Text('Skaner QR'),
          subtitle: Text('Zeskanuj kod wystawcy po wykonaniu zadania.'),
        ),
        Expanded(
          child: MobileScanner(
            onDetect: _onDetect,
            fit: BoxFit.cover,
          ),
        ),
      ],
    );
  }
}


/// --- MÓJ QR (dla wystawcy/admina) ---
class ExhibitorQrPage extends StatelessWidget {
  const ExhibitorQrPage({super.key, required this.exhibitorId, required this.exhibitorName});
  final String exhibitorId;
  final String exhibitorName;

  @override
  Widget build(BuildContext context) {
    final payload = 'EXHIBITOR:$exhibitorId';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Mój kod QR – $exhibitorName', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 16),
            Card(
              elevation: 0.5,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: QrImageView(
                  data: payload,
                  version: QrVersions.auto,
                  size: 240,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('ID wystawcy: $exhibitorId', style: TextStyle(color: Colors.grey[700])),
            const SizedBox(height: 8),
            const Text('Uczestnik zeskanuje ten kod, aby dostać 1 punkt.'),
          ],
        ),
      ),
    );
  }
}

/// --- RANKING (dla admina) ---
/// Zlicza dokumenty z kolekcji 'scans' w czasie rzeczywistym.
class AdminLeaderboardPage extends StatelessWidget {
  const AdminLeaderboardPage({super.key, required this.currentUserId});
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    // Admin widzi pełne dane — LeaderboardPage sam to ogarnia po roli 'admin'
    return LeaderboardPage(
      currentUserId: currentUserId,
      currentUserRole: 'admin',
    );
  }
}

class _LbItem {
  final String name;
  final int points;
  _LbItem({required this.name, required this.points});
}

class LeaderboardPage extends StatelessWidget {
  const LeaderboardPage({
    super.key,
    required this.currentUserId,
    required this.currentUserRole,
  });

  final String currentUserId;
  final String currentUserRole; // 'user' | 'exhibitor' | 'admin'

  bool get _isAdmin => currentUserRole == 'admin';

  String _maskPart(String s) {
    if (s.isEmpty) return '***';
    final head = s.length <= 3 ? s : s.substring(0, 3);
    // wymaganie: pierwsze 3 litery, reszta kropki
    return s.length > 3 ? '$head...' : head;
  }

  /// Z danych usera wyciąga imię i nazwisko (preferuje firstName/lastName z Firestore,
  /// w razie braku próbuje rozbić displayName).
  (String first, String last) _namesFromUserDoc(Map<String, dynamic>? data) {
    if (data == null) return ('Uczestnik', '');
    final fn = (data['firstName'] as String?)?.trim();
    final ln = (data['lastName'] as String?)?.trim();
    if (fn != null && fn.isNotEmpty && ln != null && ln.isNotEmpty) {
      return (fn, ln);
    }
    final dn = (data['displayName'] as String?)?.trim() ?? '';
    if (dn.isEmpty) return ('Uczestnik', '');
    final parts = dn.split(RegExp(r'\s+'));
    final first = parts.isNotEmpty ? parts.first : dn;
    final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    return (first, last);
  }

  @override
  Widget build(BuildContext context) {
    final scansStream = FirebaseFirestore.instance
        .collection('scans')
        .orderBy('createdAt', descending: false)
        .snapshots();

    final usersStream =
    FirebaseFirestore.instance.collection('users').snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: scansStream,
      builder: (context, scansSnap) {
        if (!scansSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        // Zlicz punkty per userId
        final counts = <String, int>{};
        for (final d in scansSnap.data!.docs) {
          final data = d.data() as Map<String, dynamic>? ?? {};
          final uid = data['userId'] as String? ?? '';
          if (uid.isEmpty) continue;
          counts[uid] = (counts[uid] ?? 0) + 1;
        }

        // Jeśli nikt nic nie zeskanował, pokaż pusty ekran
        if (counts.isEmpty) {
          return const Center(
            child: Text('Jeszcze nikt nie zdobył punktów. Bądź pierwszy!'),
          );
        }

        // Drugi strumień: mapa userów (id -> data)
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: usersStream,
          builder: (context, usersSnap) {
            if (!usersSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final userMap = <String, Map<String, dynamic>>{};
            for (final doc in usersSnap.data!.docs) {
              userMap[doc.id] = doc.data();
            }

            // Zbuduj listę pozycji do sortowania
            final entries = <_LbEntry>[];
            counts.forEach((uid, pts) {
              final udata = userMap[uid];
              final (first, last) = _namesFromUserDoc(udata);
              entries.add(_LbEntry(
                userId: uid,
                firstName: first,
                lastName: last,
                points: pts,
              ));
            });

            // Sortuj: najpierw punkty malejąco, potem nazwisko/imię dla stabilności
            entries.sort((a, b) {
              final byPoints = b.points.compareTo(a.points);
              if (byPoints != 0) return byPoints;
              final byLast = a.lastName.compareTo(b.lastName);
              if (byLast != 0) return byLast;
              return a.firstName.compareTo(b.firstName);
            });

            // Zbuduj listę UI
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final e = entries[index];
                final isMe = e.userId == currentUserId;
                final rank = index + 1;

                final (first, last) = (e.firstName, e.lastName);
                final display = _isAdmin
                    ? '$first ${last.isNotEmpty ? last : ''}'.trim()
                    : '${_maskPart(first)} ${_maskPart(last)}'.trim();

                final theme = Theme.of(context);
                final color = isMe
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface;

                return ListTile(
                  leading: CircleAvatar(
                    child: Text('$rank'),
                  ),
                  title: RichText(
                    text: TextSpan(
                      style: theme.textTheme.titleMedium!
                          .copyWith(color: color, fontWeight: isMe ? FontWeight.w600 : null),
                      children: [
                        TextSpan(text: display),
                        if (isMe) TextSpan(text: '  (Ty)', style: TextStyle(color: color)),
                      ],
                    ),
                  ),
                  trailing: Text(
                    '${e.points} pkt',
                    style: theme.textTheme.titleMedium!
                        .copyWith(color: color, fontWeight: isMe ? FontWeight.w700 : null),
                  ),
                  tileColor: isMe
                      ? theme.colorScheme.primary.withOpacity(0.08)
                      : null,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _LbEntry {
  final String userId;
  final String firstName;
  final String lastName;
  final int points;
  _LbEntry({
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.points,
  });
}

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key, required this.currentUserId});
  final String currentUserId;

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  final _search = TextEditingController();
  final _roles = const ['user', 'exhibitor', 'admin'];

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _changeRole(String uid, String newRole) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'role': newRole,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _snack('Zmieniono rolę na: $newRole');
    } catch (e) {
      _snack('Nie udało się zmienić roli: $e');
    }
  }

  Future<void> _deleteUserDoc(String uid) async {
    if (uid == widget.currentUserId) {
      _snack('Nie możesz usunąć własnego konta z tej listy.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usunąć użytkownika?'),
        content: const Text(
          'To usunie dokument w Firestore.\n'
              'Uwaga: nie usuwa konta w Firebase Auth.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Usuń')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();
      _snack('Usunięto dokument użytkownika.');
    } catch (e) {
      _snack('Nie udało się usunąć: $e');
    }
  }

  Future<void> _editUser(String uid, Map<String, dynamic> data) async {
    final firstName = TextEditingController(text: (data['firstName'] as String?) ?? '');
    final lastName  = TextEditingController(text: (data['lastName']  as String?) ?? '');
    final email     = TextEditingController(text: (data['email']     as String?) ?? '');
    final phone     = TextEditingController(text: (data['phone']     as String?) ?? '');
    final company   = TextEditingController(text: (data['company']   as String?) ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edytuj użytkownika'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: firstName, decoration: const InputDecoration(labelText: 'Imię', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: lastName,  decoration: const InputDecoration(labelText: 'Nazwisko', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: email,     decoration: const InputDecoration(labelText: 'Email (Firestore)', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: phone,     decoration: const InputDecoration(labelText: 'Telefon', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: company,   decoration: const InputDecoration(labelText: 'Firma (opcjonalnie)', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              const Text(
                'Zmiana emaila tutaj nie zmienia adresu w Firebase Auth.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Zapisz')),
        ],
      ),
    );

    if (saved != true) return;

    final fn = firstName.text.trim();
    final ln = lastName.text.trim();
    final dn = [fn, ln].where((s) => s.isNotEmpty).join(' ').trim();

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'firstName': fn,
        'lastName': ln,
        'displayName': dn.isNotEmpty ? dn : (data['displayName'] ?? 'Uczestnik'),
        'email': email.text.trim(),
        'phone': phone.text.trim(),
        'company': company.text.trim().isEmpty ? null : company.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _snack('Zapisano zmiany.');
    } catch (e) {
      _snack('Nie udało się zapisać: $e');
    }
  }

  Future<void> _resetPasswordEmail(String email) async {
    if (email.isEmpty) {
      _snack('Ten użytkownik nie ma zapisanego adresu e-mail.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _snack('Wysłano e-mail do resetu hasła.');
    } catch (e) {
      _snack('Nie udało się wysłać resetu: $e');
    }
  }

  Future<void> _pickRoleDialog(String uid, String currentRole) async {
    String sel = currentRole;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zmień rolę'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _roles.map((r) {
            return RadioListTile<String>(
              value: r,
              groupValue: sel,
              onChanged: (v) => setState(() => sel = v ?? sel),
              title: Text(r),
              dense: true,
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Zapisz')),
        ],
      ),
    );
    if (ok == true && sel != currentRole) {
      await _changeRole(uid, sel);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersStream = FirebaseFirestore.instance
        .collection('users')
        .orderBy('displayName', descending: false)
        .snapshots();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Szukaj po imieniu, emailu, firmie...',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: usersStream,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snap.hasData) {
                return const Center(child: Text('Brak danych.'));
              }

              final q = _search.text.trim().toLowerCase();
              final docs = snap.data!.docs.where((d) {
                if (q.isEmpty) return true;
                final m = d.data();
                final dn = (m['displayName'] as String? ?? '').toLowerCase();
                final em = (m['email'] as String? ?? '').toLowerCase();
                final co = (m['company'] as String? ?? '').toLowerCase();
                return dn.contains(q) || em.contains(q) || co.contains(q);
              }).toList();

              if (docs.isEmpty) {
                return const Center(child: Text('Nic nie znaleziono.'));
              }

              return LayoutBuilder(
                builder: (context, cons) {
                  final narrow = cons.maxWidth < 480; // telefon

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final doc = docs[i];
                      final uid = doc.id;
                      final data = doc.data();
                      final role = (data['role'] as String?) ?? 'user';
                      final fn = (data['firstName'] as String?) ?? '';
                      final ln = (data['lastName']  as String?) ?? '';
                      final dn = (data['displayName'] as String?) ?? [fn, ln].where((s) => s.isNotEmpty).join(' ');
                      final em = (data['email'] as String?) ?? '';
                      final ph = (data['phone'] as String?) ?? '';
                      final co = (data['company'] as String?) ?? '';

                      final subtitleText = [
                        if (em.isNotEmpty) em,
                        if (ph.isNotEmpty) ph,
                        if (co.isNotEmpty) 'Firma: $co',
                      ].join(' • ');

                      Widget trailing;
                      if (narrow) {
                        // WĄSKI EKRAN → jedno menu z akcjami
                        trailing = PopupMenuButton<String>(
                          tooltip: 'Akcje',
                          onSelected: (v) async {
                            switch (v) {
                              case 'role':
                                await _pickRoleDialog(uid, role);
                                break;
                              case 'edit':
                                await _editUser(uid, data);
                                break;
                              case 'reset':
                                await _resetPasswordEmail(em);
                                break;
                              case 'delete':
                                await _deleteUserDoc(uid);
                                break;
                            }
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(value: 'role',  child: ListTile(leading: Icon(Icons.verified_user_outlined), title: Text('Zmień rolę'))),
                            const PopupMenuItem(value: 'edit',  child: ListTile(leading: Icon(Icons.edit_outlined),           title: Text('Edytuj'))),
                            const PopupMenuItem(value: 'reset', child: ListTile(leading: Icon(Icons.lock_reset_outlined),    title: Text('Reset hasła (e-mail)'))),
                            const PopupMenuItem(value: 'delete',child: ListTile(leading: Icon(Icons.delete_outline),         title: Text('Usuń (Firestore)'))),
                          ],
                        );
                      } else {
                        // SZEROKI EKRAN → dropdown + ikony, ale w ograniczonej szerokości
                        trailing = ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 130,
                                child: DropdownButton<String>(
                                  isDense: true,
                                  isExpanded: true,
                                  value: role,
                                  onChanged: (val) {
                                    if (val != null) _changeRole(uid, val);
                                  },
                                  items: _roles.map((r) => DropdownMenuItem(
                                    value: r, child: Text(r, overflow: TextOverflow.ellipsis),
                                  )).toList(),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Reset hasła (e-mail)',
                                icon: const Icon(Icons.lock_reset_outlined),
                                onPressed: () => _resetPasswordEmail(em),
                              ),
                              IconButton(
                                tooltip: 'Edytuj',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _editUser(uid, data),
                              ),
                              IconButton(
                                tooltip: 'Usuń (Firestore)',
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                onPressed: () => _deleteUserDoc(uid),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: CircleAvatar(child: Text(dn.isNotEmpty ? dn[0].toUpperCase() : '?')),
                        title: Text(
                          dn.isEmpty ? 'Uczestnik' : dn,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          subtitleText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: trailing,
                        // trochę ciaśniej
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        isThreeLine: false,
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// Mała pomoc do Switch.thumbIcon (żeby nie robić długiej logiki w miejscu)
bool valOr(bool cond) => cond;

class ExhibitorsPage extends StatelessWidget {
  const ExhibitorsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final exhibitorsStream = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'exhibitor')
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: exhibitorsStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snap.hasData) {
          return const Center(child: Text('Brak danych.'));
        }

        final docs = snap.data!.docs;

        if (docs.isEmpty) {
          return const Center(child: Text('Brak wystawców.'));
        }

        // Możesz chcieć sortować po company — jeśli pole bywa puste,
        // posortujemy lokalnie z fallbackiem na displayName.
        final items = docs.map((d) {
          final data = d.data();
          final company = (data['company'] as String?)?.trim();
          final displayName = (data['displayName'] as String?)?.trim() ?? '';
          final title = (company != null && company.isNotEmpty)
              ? company
              : displayName.isNotEmpty
              ? displayName
              : 'Wystawca';
          return (id: d.id, title: title);
        }).toList()
          ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final item = items[i];
            return ListTile(
              leading: const Icon(Icons.store_mall_directory_outlined),
              title: Text(item.title),
              // (opcjonalnie) na przyszłość: onTap → pokaż szczegóły stoiska
            );
          },
        );
      },
    );
  }
}
