import 'dart:io';

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String supabaseUrl = 'https://lhziuykazsjhsqsnjgwp.supabase.co';
const String supabasePublishableKey =
    'sb_publishable_BDU_-L01N1WArtn57xfVPg_GI4V6z3_';

final supabase = Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );

  runApp(const MessAttendanceApp());
}

class MessAttendanceApp extends StatelessWidget {
  const MessAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MESS Attendance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'sans',
        scaffoldBackgroundColor: const Color(0xFFF4F4F4),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.black,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF4F4F4),
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.black, width: 1.5),
          ),
        ),
      ),
      home: const SessionGate(),
    );
  }
}

// ============================================================
// SESSION GATE
// ============================================================

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  final AppLinks _appLinks = AppLinks();

  StreamSubscription<Uri>? _linkSubscription;

  bool _checkingRecovery = true;
  bool _isRecovery = false;

  @override
  void initState() {
    super.initState();

    _setupAuthListener();
    _setupDeepLinks();
  }

  void _setupAuthListener() {
    supabase.auth.onAuthStateChange.listen((data) {
      final event = data.event;

      if (event == AuthChangeEvent.passwordRecovery) {
        if (!mounted) return;

        setState(() {
          _isRecovery = true;
          _checkingRecovery = false;
        });
      }
    });
  }

  Future<void> _setupDeepLinks() async {
    try {
      // Handles the link when the app is already running.
      _linkSubscription = _appLinks.uriLinkStream.listen((uri) async {
        await _handleRecoveryUri(uri);
      });

      // Handles the link when the app was completely closed.
      final initialUri = await _appLinks.getInitialLink();

      if (initialUri != null) {
        await _handleRecoveryUri(initialUri);
      }
    } catch (_) {
      // If there is no deep link, continue normally.
    } finally {
      if (mounted) {
        setState(() {
          _checkingRecovery = false;
        });
      }
    }
  }

  Future<void> _handleRecoveryUri(Uri uri) async {
    try {
      debugPrint('Recovery URI: $uri');

      // Supabase recovery links may contain authentication
      // information in the URL fragment.
      final fragment = uri.fragment;

      if (fragment.isEmpty) {
        return;
      }

      final fragmentParams = Uri.splitQueryString(fragment);

      final accessToken = fragmentParams['access_token'];
      final refreshToken = fragmentParams['refresh_token'];
      final type = fragmentParams['type'];

      debugPrint('Recovery type: $type');

      if (accessToken == null || refreshToken == null) {
        return;
      }

      await supabase.auth.setSession(refreshToken, accessToken: accessToken);

      if (!mounted) return;

      setState(() {
        _isRecovery = true;
        _checkingRecovery = false;
      });
    } catch (e) {
      debugPrint('Recovery error: $e');
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingRecovery) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_isRecovery) {
      return const ResetPasswordPage();
    }

    final session = supabase.auth.currentSession;

    if (session == null) {
      return const LoginPage();
    }

    return const HomePage();
  }
}

// ============================================================
// LOGIN
// ============================================================

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final regIdController = TextEditingController();
  final passwordController = TextEditingController();

  bool loading = false;
  bool obscurePassword = true;

  @override
  void dispose() {
    emailController.dispose();
    regIdController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> login() async {
    final email = emailController.text.trim();
    final regId = regIdController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || regId.isEmpty || password.isEmpty) {
      showMessage('Please fill all fields.');
      return;
    }

    if (!email.contains('@')) {
      showMessage('Please enter a valid email.');
      return;
    }

    setState(() => loading = true);

    try {
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;

      if (user == null) {
        throw Exception('Login failed');
      }

      // Registration ID is verified against the authenticated
      // user's profile. It is NOT trusted as an authorization ID.
      final profile = await supabase
          .from('student_profiles')
          .select('reg_id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (profile == null ||
          profile['reg_id'].toString().trim().toLowerCase() !=
              regId.toLowerCase()) {
        await supabase.auth.signOut();

        if (mounted) {
          showMessage('Invalid login credentials.');
        }
        return;
      }

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomePage()),
        (route) => false,
      );
    } on AuthException {
      showMessage('Invalid login credentials.');
    } catch (_) {
      showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> forgotPassword() async {
    final emailControllerLocal = TextEditingController(
      text: emailController.text.trim(),
    );

    final email = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Forgot Password'),
          content: TextField(
            controller: emailControllerLocal,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Registered email'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, emailControllerLocal.text.trim());
              },
              child: const Text('Send'),
            ),
          ],
        );
      },
    );

    emailControllerLocal.dispose();

    if (email == null || email.isEmpty) return;

    try {
      await supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: 'io.messattendance://reset-password/',
      );

      if (!mounted) return;

      showMessage('Password reset email sent. Check your inbox.');
    } on AuthException catch (e) {
      if (!mounted) return;

      showMessage(e.message);
    } catch (_) {
      if (!mounted) return;

      showMessage('Unable to send reset email. Please try again.');
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.restaurant_rounded,
                    size: 58,
                    color: Colors.black,
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'MESS Attendance',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Student attendance',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 40),

                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),

                  const SizedBox(height: 14),

                  TextField(
                    controller: regIdController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Registration ID',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),

                  const SizedBox(height: 14),

                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    onSubmitted: (_) => loading ? null : login(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: loading ? null : login,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'LOGIN',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  TextButton(
                    onPressed: loading ? null : forgotPassword,
                    child: const Text('Forgot Password?'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// HOME
// ============================================================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, dynamic>? profile;
  Map<String, dynamic>? attendance;

  bool loading = true;
  String? profilePhotoPath;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    if (!mounted) return;

    setState(() => loading = true);

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        goToLogin();
        return;
      }

      final profileResult = await supabase
          .from('student_profiles')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (profileResult == null) {
        throw Exception('Profile not found');
      }

      final today = _todayString();

      final attendanceResult = await supabase
          .from('meal_attendance')
          .select()
          .eq('student_id', profileResult['id'])
          .eq('attendance_date', today)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        profile = Map<String, dynamic>.from(profileResult);
        attendance = attendanceResult == null
            ? null
            : Map<String, dynamic>.from(attendanceResult);
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() => loading = false);

      showMessage('Unable to load your information.');
    }
  }

  String _todayString() {
    final now = DateTime.now();
    return DateFormat('yyyy-MM-dd').format(now);
  }

  Future<void> markMeal(String meal) async {
    if (profile == null) return;

    try {
      final result = await supabase.rpc('mark_meal', params: {'p_meal': meal});

      final status = result.toString();

      if (status == 'marked' || status == 'already_done') {
        await loadData();

        if (mounted) {
          showMessage(
            status == 'already_done'
                ? 'Already marked.'
                : 'Attendance recorded.',
          );
        }
      } else {
        if (mounted) {
          showMessage('Failed — Try Again');
        }
      }
    } catch (_) {
      if (mounted) {
        showMessage('Failed — Try Again');
      }
    }
  }

  String mealStatus(String meal) {
    if (attendance == null) return '-';

    switch (meal) {
      case 'breakfast':
        return attendance!['breakfast_status']?.toString() ?? '-';
      case 'lunch':
        return attendance!['lunch_status']?.toString() ?? '-';
      case 'dinner':
        return attendance!['dinner_status']?.toString() ?? '-';
      default:
        return '-';
    }
  }

  void openMeal(String meal) {
    final status = mealStatus(meal);

    showDialog(
      context: context,
      builder: (_) => MealDialog(
        meal: meal,
        status: status,
        onMark: () async {
          Navigator.of(context).pop();

          await markMeal(meal);
        },
      ),
    );
  }

  Future<void> selectProfilePhoto() async {
    try {
      final picker = ImagePicker();

      final image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 2000,
        maxHeight: 2000,
      );

      if (image == null) return;

      final directory = await getApplicationDocumentsDirectory();

      final target = File('${directory.path}/mess_profile_photo.jpg');

      await File(image.path).copy(target.path);

      if (!mounted) return;

      setState(() {
        profilePhotoPath = target.path;
      });

      showMessage('Profile photo updated on this device.');
    } catch (_) {
      showMessage('Unable to update profile photo.');
    }
  }

  Future<void> logout() async {
    await supabase.auth.signOut();

    if (!mounted) return;

    goToLogin();
  }

  void goToLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (profile == null) {
      return Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: loadData,
            child: const Text('Try Again'),
          ),
        ),
      );
    }

    final name = profile!['name']?.toString() ?? '';
    final regId = profile!['reg_id']?.toString() ?? '';
    final room = profile!['room_no']?.toString() ?? '';
    final batch = profile!['batch']?.toString() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'MESS Attendance',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'history') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HistoryPage()),
                );
              }

              if (value == 'logout') {
                logout();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'history',
                child: Text('Attendance History'),
              ),
              PopupMenuItem(value: 'logout', child: Text('Logout')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: loadData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
          children: [
            ProfileCard(
              name: name,
              regId: regId,
              room: room,
              batch: batch,
              photoPath: profilePhotoPath,
              onPhotoTap: selectProfilePhoto,
            ),

            const SizedBox(height: 24),

            const Text(
              "Today's Meals",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),

            const SizedBox(height: 12),

            MealCard(
              title: 'Breakfast',
              icon: Icons.free_breakfast_rounded,
              status: mealStatus('breakfast'),
              onTap: () => openMeal('breakfast'),
            ),

            MealCard(
              title: 'Lunch',
              icon: Icons.lunch_dining_rounded,
              status: mealStatus('lunch'),
              onTap: () => openMeal('lunch'),
            ),

            MealCard(
              title: 'Dinner',
              icon: Icons.dinner_dining_rounded,
              status: mealStatus('dinner'),
              onTap: () => openMeal('dinner'),
            ),

            const SizedBox(height: 12),

            Card(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE5E5E5)),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                leading: const CircleAvatar(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  child: Icon(Icons.history),
                ),
                title: const Text(
                  'Attendance History',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text('View previous months'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HistoryPage()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// PROFILE CARD
// ============================================================

class ProfileCard extends StatelessWidget {
  final String name;
  final String regId;
  final String room;
  final String batch;
  final String? photoPath;
  final VoidCallback onPhotoTap;

  const ProfileCard({
    super.key,
    required this.name,
    required this.regId,
    required this.room,
    required this.batch,
    required this.photoPath,
    required this.onPhotoTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoPath != null && File(photoPath!).existsSync();

    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5E5E5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            GestureDetector(
              onTap: onPhotoTap,
              child: CircleAvatar(
                radius: 38,
                backgroundColor: Colors.black,
                backgroundImage: hasPhoto ? FileImage(File(photoPath!)) : null,
                child: hasPhoto
                    ? null
                    : const Icon(Icons.person, size: 38, color: Colors.white),
              ),
            ),

            const SizedBox(width: 18),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Reg ID: $regId',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  Text(
                    'Room: $room',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  Text(
                    'Batch: $batch',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// MEAL CARD
// ============================================================

class MealCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String status;
  final VoidCallback onTap;

  const MealCard({
    super.key,
    required this.title,
    required this.icon,
    required this.status,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final done = status == 'P';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5E5E5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Colors.white, size: 30),
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      done ? 'Done' : 'Tap to mark meal',
                      style: TextStyle(
                        color: done ? Colors.black : Colors.black54,
                        fontWeight: done ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),

              Icon(
                done ? Icons.check_circle : Icons.chevron_right,
                color: Colors.black,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// MEAL DIALOG
// ============================================================

class MealDialog extends StatelessWidget {
  final String meal;
  final String status;
  final Future<void> Function() onMark;

  const MealDialog({
    super.key,
    required this.meal,
    required this.status,
    required this.onMark,
  });

  String get title {
    switch (meal) {
      case 'breakfast':
        return 'BREAKFAST';
      case 'lunch':
        return 'LUNCH';
      case 'dinner':
        return 'DINNER';
      default:
        return meal.toUpperCase();
    }
  }

  IconData get icon {
    switch (meal) {
      case 'breakfast':
        return Icons.free_breakfast_rounded;
      case 'lunch':
        return Icons.lunch_dining_rounded;
      case 'dinner':
        return Icons.dinner_dining_rounded;
      default:
        return Icons.restaurant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = status == 'P';

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, color: Colors.white, size: 55),
            ),

            const SizedBox(height: 22),

            Text(
              title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),

            const SizedBox(height: 10),

            if (done) ...[
              const Icon(Icons.check_circle, size: 44, color: Colors.black),
              const SizedBox(height: 10),
              const Text(
                'DONE',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              const Text(
                'Meal attendance recorded.',
                textAlign: TextAlign.center,
              ),
            ] else ...[
              const Text(
                'Meal not marked',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () async {
                    await onMark();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'GOT MEAL',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 12),

            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// HISTORY
// ============================================================

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  List<Map<String, dynamic>> records = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadHistory();
  }

  String _dateOnly(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  Future<void> loadHistory() async {
    setState(() => loading = true);

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        if (mounted) Navigator.pop(context);
        return;
      }

      final profile = await supabase
          .from('student_profiles')
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (profile == null) {
        throw Exception('Profile missing');
      }

      final firstDay = DateTime(selectedMonth.year, selectedMonth.month, 1);

      final nextMonth = DateTime(
        selectedMonth.year,
        selectedMonth.month + 1,
        1,
      );

      final result = await supabase
          .from('meal_attendance')
          .select()
          .eq('student_id', profile['id'])
          .gte('attendance_date', _dateOnly(firstDay))
          .lt('attendance_date', _dateOnly(nextMonth))
          .order('attendance_date');

      if (!mounted) return;

      setState(() {
        records = List<Map<String, dynamic>>.from(
          result.map((row) => Map<String, dynamic>.from(row)),
        );
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        records = [];
        loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load attendance history.')),
      );
    }
  }

  void previousMonth() {
    setState(() {
      selectedMonth = DateTime(selectedMonth.year, selectedMonth.month - 1);
    });

    loadHistory();
  }

  void nextMonth() {
    final now = DateTime.now();

    final next = DateTime(selectedMonth.year, selectedMonth.month + 1);

    final currentMonth = DateTime(now.year, now.month);

    if (next.isAfter(currentMonth)) return;

    setState(() {
      selectedMonth = next;
    });

    loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final monthTitle = DateFormat('MMMM yyyy').format(selectedMonth);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Attendance History',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Card(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFFE5E5E5)),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: previousMonth,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      monthTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: nextMonth,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : records.isEmpty
                ? const Center(
                    child: Text('No attendance records for this month.'),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
                    children: [_historyHeader(), ...records.map(_historyRow)],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _historyHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              'Date',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'B',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'L',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'D',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyRow(Map<String, dynamic> record) {
    final date = record['attendance_date'].toString();

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E5E5)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              DateFormat('dd MMM').format(DateTime.parse(date)),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: _statusCell(record['breakfast_status'])),
          Expanded(child: _statusCell(record['lunch_status'])),
          Expanded(child: _statusCell(record['dinner_status'])),
        ],
      ),
    );
  }

  Widget _statusCell(dynamic value) {
    final status = value?.toString() ?? '-';

    return Center(
      child: Text(
        status,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 16,
          color: status == 'P' ? Colors.black : Colors.black38,
        ),
      ),
    );
  }
}

//--------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------- forgot password page --------------------------------------------------
//-------------------------------------------------------------------------------------------------------------------------

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final passwordController = TextEditingController();
  final confirmController = TextEditingController();

  bool loading = false;
  bool obscurePassword = true;
  bool obscureConfirm = true;

  @override
  void dispose() {
    passwordController.dispose();
    confirmController.dispose();
    super.dispose();
  }

  Future<void> updatePassword() async {
    final password = passwordController.text;
    final confirm = confirmController.text;

    if (password.length < 6) {
      showMessage('Password must be at least 6 characters.');
      return;
    }

    if (password != confirm) {
      showMessage('Passwords do not match.');
      return;
    }

    setState(() => loading = true);

    try {
      await supabase.auth.updateUser(UserAttributes(password: password));

      if (!mounted) return;

      try {
        await supabase.auth.updateUser(UserAttributes(password: password));

        await supabase.auth.signOut();

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password updated successfully. Please login.'),
          ),
        );

        await Future.delayed(const Duration(milliseconds: 800));

        if (!mounted) return;

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      } on AuthException catch (e) {
        if (mounted) {
          showMessage(e.message);
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        showMessage(e.message);
      }
    } catch (_) {
      if (mounted) {
        showMessage('Unable to update password. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Reset Password',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.lock_reset_rounded, size: 64),

                  const SizedBox(height: 24),

                  const Text(
                    'Create a new password',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Enter your new password below.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),

                  const SizedBox(height: 32),

                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  TextField(
                    controller: confirmController,
                    obscureText: obscureConfirm,
                    decoration: InputDecoration(
                      labelText: 'Confirm Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            obscureConfirm = !obscureConfirm;
                          });
                        },
                        icon: Icon(
                          obscureConfirm
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: loading ? null : updatePassword,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'UPDATE PASSWORD',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
} 