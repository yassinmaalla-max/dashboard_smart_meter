import 'dart:convert'; // ✅ Ajout pour jsonDecode
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http; 
import 'package:universal_html/html.dart' as html; 
import 'firebase_options.dart';
import 'screens/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  try {
    await FirebaseAuth.instance.signInAnonymously();
  } catch (e) {
    debugPrint("Erreur Auth: $e");
  }
  runApp(const SmartMeterApp());
}

class SmartMeterApp extends StatefulWidget {
  const SmartMeterApp({super.key});
  @override
  State<SmartMeterApp> createState() => _SmartMeterAppState();
}

class _SmartMeterAppState extends State<SmartMeterApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  final String _currentVersion = "1.0.0"; // ⚠️ À changer à chaque déploiement

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
  }

  Future<void> _checkForUpdates() async {
    try {
      // ✅ CORRECTION : On utilise une URL relative (marche en local et en prod)
      final response = await http.get(
        Uri.parse('version.json?t=${DateTime.now().millisecondsSinceEpoch}'),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String serverVersion = data['version'] ?? "1.0.0";

        if (serverVersion != _currentVersion && mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('Mise à jour disponible'),
              content: const Text('Une nouvelle version de l\'application est disponible. Voulez-vous la charger maintenant ?'),
              actions: [
                TextButton(
                  onPressed: () {
                    html.window.location.reload();
                  },
                  child: const Text('Mettre à jour', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      // On ignore l'erreur en mode local si le fichier n'existe pas
      debugPrint("Vérification MAJ ignorée (fichier absent ou hors-ligne)");
    }
  }

  void _toggleTheme() => setState(() => _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Meter Pro',
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F6F8),
        primaryColor: const Color(0xFFE67E22),
        cardColor: Colors.white,
        dividerColor: Colors.grey.shade300,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1115),
        primaryColor: const Color(0xFFE67E22),
        cardColor: const Color(0xFF1A1D24),
        dividerColor: Colors.white12,
        useMaterial3: true,
      ),
      home: DashboardScreen(isDarkMode: _themeMode == ThemeMode.dark, onToggleTheme: _toggleTheme),
      debugShowCheckedModeBanner: false,
    );
  }
}