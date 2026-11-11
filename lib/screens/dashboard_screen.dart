import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart'; // ✅ Toujours nécessaire pour FlSpot et FlTouchEvent
import 'package:intl/intl.dart'; // ✅ Toujours nécessaire pour DateFormat

import 'steg_estimate_dialog.dart';
import '../widgets/gauge_painter.dart';
import '../widgets/dashboard_chart.dart';
import 'settings_screen.dart';
import 'report_dialog.dart';
import 'ev_charging_dialog.dart';
import 'limit_dialog.dart';

class DashboardScreen extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback onToggleTheme;
  const DashboardScreen({super.key, required this.isDarkMode, required this.onToggleTheme});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DatabaseReference _realtimeRef = FirebaseDatabase.instance.ref('compteur/temps_reel');
  final DatabaseReference _historyRef = FirebaseDatabase.instance.ref('historique/live');
  
  StreamSubscription<DatabaseEvent>? _rtSubscription;
  StreamSubscription<DatabaseEvent>? _historySubscription;
  StreamSubscription<DatabaseEvent>? _timeSubscription;
  StreamSubscription<DatabaseEvent>? _limitSubscription;

  final String _adminEmail = "admin@smartmeter.com"; 
  bool _isAdmin = false;
  
  double _tension = 0.0, _courant = 0.0, _puissance = 0.0, _energieTotale = 0.0;
  double _puissanceProd = 0.0, _energieTotaleProd = 0.0;
  int _offlinePending = 0;
  DateTime? _lastSeenTime;
  final Duration _offlineThreshold = const Duration(minutes: 2);
  final double _alertThreshold = 2000.0;

  double _energieBaseReset = -1.0;
  double _energieBaseJournaliere = -1.0;
  double _energieBaseJournaliereProd = -1.0;
  int _lastDay = -1;

  int? _resetSessionTime;
  int? _pzemResetTime;

  // ✅ Variables pour les limites
  double _dailyLimit = 0.0;
  double _monthlyLimit = 0.0;
  bool _limitAlertTriggered = false;

  int _hourRange = 24; 
  MetricType _selectedMetric = MetricType.puissance;
  PeriodType _selectedPeriod = PeriodType.day;
  DateTime _selectedDate = DateTime.now();
  
  DateTime _customStart = DateTime.now().subtract(const Duration(days: 1));
  DateTime _customEnd = DateTime.now();
  DateTime? _tempStartSelection;

  List<ReportComponent> _reportComponents = [];
  bool _isSelectingForReport = false;
  int _reportComponentIndex = 0;
  bool _isSelectingReportStart = true;

  final List<Map<String, dynamic>> _historyData = [];

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
    _setupFirebaseListeners();
    Future.delayed(const Duration(seconds: 2), () => _autoSyncOfflineData());
  }

  void _checkAdminStatus() {
    final user = FirebaseAuth.instance.currentUser;
    setState(() => _isAdmin = (user != null && user.email == _adminEmail));
  }

  bool get _isEspOnline => _lastSeenTime != null && DateTime.now().difference(_lastSeenTime!) < _offlineThreshold;

  Future<void> _loadResetBase(double currentEnergy) async {
    final snapBase = await FirebaseDatabase.instance.ref('compteur/reset_base').get();
    final snapTime = await FirebaseDatabase.instance.ref('compteur/reset_time').get();
    
    if (snapBase.exists && snapBase.value != null) {
      setState(() {
        _energieBaseReset = (snapBase.value as num).toDouble();
        if (snapTime.exists) _resetSessionTime = snapTime.value as int?;
      });
    } else {
      setState(() {
        _energieBaseReset = currentEnergy;
        _resetSessionTime = DateTime.now().millisecondsSinceEpoch;
      });
      await FirebaseDatabase.instance.ref('compteur/reset_base').set(currentEnergy);
      await FirebaseDatabase.instance.ref('compteur/reset_time').set(DateTime.now().millisecondsSinceEpoch);
    }
  }

  void _setupFirebaseListeners() {
    _rtSubscription = _realtimeRef.onValue.listen((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null) {
        setState(() {
          _tension = (data['tension'] ?? 0).toDouble();
          _courant = (data['courant'] ?? 0).toDouble();
          _puissance = (data['puissance'] ?? 0).toDouble();
          _energieTotale = (data['energie_totale'] ?? 0).toDouble();
          _puissanceProd = (data['puissance_production'] ?? 0).toDouble();
          _energieTotaleProd = (data['energie_totale_production'] ?? 0).toDouble();
          _offlinePending = (data['offline_pending'] ?? 0).toInt();

          if (data['timestamp'] != null) {
            _lastSeenTime = DateTime.fromMillisecondsSinceEpoch((data['timestamp'] as int) * 1000);
          } else {
            _lastSeenTime = DateTime.now();
          }

          DateTime now = DateTime.now();
          if (_lastDay == -1) {
            _lastDay = now.day;
            _energieBaseJournaliere = _energieTotale;
            _energieBaseJournaliereProd = _energieTotaleProd;
          } else if (now.day != _lastDay) {
            _lastDay = now.day;
            _energieBaseJournaliere = _energieTotale;
            _energieBaseJournaliereProd = _energieTotaleProd;
          }
        });

        if (_energieBaseReset == -1.0 && _energieTotale > 0) {
          _loadResetBase(_energieTotale);
        }
        
        _checkLimits(); // ✅ Vérification des limites
      }
    });

    _timeSubscription = FirebaseDatabase.instance.ref('compteur/pzem_reset_time').onValue.listen((event) {
      if (event.snapshot.exists) {
        setState(() => _pzemResetTime = event.snapshot.value as int?);
      }
    });

    // ✅ Écoute des limites
    _limitSubscription = FirebaseDatabase.instance.ref('config/limits').onValue.listen((event) {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        setState(() {
          _dailyLimit = (data['daily'] ?? 0.0).toDouble();
          _monthlyLimit = (data['monthly'] ?? 0.0).toDouble();
        });
        _checkLimits();
      }
    });

    _loadHistory();
  }

  void _loadHistory() {
    _historySubscription = _historyRef.onValue.listen((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null) {
        List<Map<String, dynamic>> loadedData = [];
        data.forEach((key, value) {
          final map = value as Map<dynamic, dynamic>;
          loadedData.add({
            'time': DateTime.fromMillisecondsSinceEpoch((map['timestamp'] ?? 0) * 1000),
            'v': (map['tension'] ?? 0).toDouble(),
            'i': (map['courant'] ?? 0).toDouble(),
            'p': (map['puissance'] ?? 0).toDouble(),
            'p_prod': (map['puissance_production'] ?? 0).toDouble(),
          });
        });
        loadedData.sort((a, b) => (a['time'] as DateTime).compareTo(b['time'] as DateTime));
        setState(() {
          _historyData.clear();
          _historyData.addAll(loadedData);
        });
      }
    });
  }

  void _autoSyncOfflineData() async {
    try {
      final rawRef = FirebaseDatabase.instance.ref('offline_raw/data');
      final snapshot = await rawRef.get();
      if (snapshot.exists && snapshot.value != null) {
        String rawData = snapshot.value as String;
        List<String> lines = rawData.split('\n');
        Map<String, dynamic> updates = {};
        for (String line in lines) {
          if (line.trim().isEmpty) continue;
          List<String> parts = line.split(';');
          if (parts.length >= 5) {
            String timestamp = parts[0];
            updates['historique/live/$timestamp'] = {
              'tension': double.tryParse(parts[1]) ?? 0.0,
              'courant': double.tryParse(parts[2]) ?? 0.0,
              'puissance': double.tryParse(parts[3]) ?? 0.0,
              'energie_totale': double.tryParse(parts[4]) ?? 0.0,
              'timestamp': int.parse(timestamp),
              'from_offline': true
            };
          }
        }
        if (updates.isNotEmpty) await FirebaseDatabase.instance.ref().update(updates);
        await rawRef.remove();
        await FirebaseDatabase.instance.ref('commandes/clear_offline').set(true);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Données hors-ligne synchronisées !'), backgroundColor: Colors.green));
      }
    } catch (e) {
      debugPrint("Erreur Synchro : $e");
    }
  }

  void _resetData() async {
    setState(() {
      _energieBaseReset = _energieTotale;
      _resetSessionTime = DateTime.now().millisecondsSinceEpoch;
    });
    await FirebaseDatabase.instance.ref('compteur/reset_base').set(_energieTotale);
    await FirebaseDatabase.instance.ref('compteur/reset_time').set(ServerValue.timestamp);
    
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Compteur de session (Reset) sauvegardé !'), backgroundColor: Colors.green));
  }

  void _handleGraphTouch(FlTouchEvent event, LineTouchResponse? touchResponse) {
    if (event is FlTapUpEvent && touchResponse != null && touchResponse.lineBarSpots != null) {
      final spot = touchResponse.lineBarSpots!.first;
      DateTime clickedTime;
      if (_selectedPeriod == PeriodType.custom) {
        clickedTime = DateTime.fromMillisecondsSinceEpoch((spot.x * 3600000).toInt());
      } else if (_selectedPeriod == PeriodType.day) {
        int hour = spot.x.floor();
        int minute = ((spot.x - hour) * 60).round();
        clickedTime = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, hour, minute);
      } else {
        clickedTime = DateTime.now();
      }

      if (_isSelectingForReport) {
        setState(() {
          if (_isSelectingReportStart) {
            _reportComponents[_reportComponentIndex].start = clickedTime;
          } else {
            _reportComponents[_reportComponentIndex].end = clickedTime;
          }
          _isSelectingForReport = false; 
        });
        _openReportDialog(); 
        return;
      }

      if (_selectedPeriod == PeriodType.custom) {
        setState(() {
          if (_tempStartSelection == null) {
            _tempStartSelection = clickedTime;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📍 Début sélectionné. Cliquez à nouveau pour définir la fin.'), duration: Duration(seconds: 2)));
          } else {
            if (clickedTime.isBefore(_tempStartSelection!)) {
              _customStart = clickedTime;
              _customEnd = _tempStartSelection!;
            } else {
              _customStart = _tempStartSelection!;
              _customEnd = clickedTime;
            }
            _tempStartSelection = null; 
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Période mise à jour !'), duration: Duration(seconds: 2), backgroundColor: Colors.green));
          }
        });
      }
    }
  }

  void _changeDate(int increment) {
    setState(() {
      if (_selectedPeriod == PeriodType.day) {
        _selectedDate = _selectedDate.add(Duration(days: increment));
        if (_selectedDate.day != DateTime.now().day || _selectedDate.month != DateTime.now().month || _selectedDate.year != DateTime.now().year) _hourRange = 24; 
      } else if (_selectedPeriod == PeriodType.month) {
        _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + increment, 1);
      } else if (_selectedPeriod == PeriodType.year) {
        _selectedDate = DateTime(_selectedDate.year + increment, 1, 1);
      }
    });
  }

  void _loginAsAdmin() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Connexion Administrateur'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email')),
              TextField(controller: passwordController, decoration: const InputDecoration(labelText: 'Mot de passe'), obscureText: true),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                try {
                  await FirebaseAuth.instance.signInWithEmailAndPassword(email: emailController.text.trim(), password: passwordController.text.trim());
                  setState(() => _isAdmin = true);
                  if (mounted) Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Connecté en tant qu\'Admin'), backgroundColor: Colors.green));
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Erreur : $e'), backgroundColor: Colors.red));
                }
              },
              child: const Text('Se connecter'),
            ),
          ],
        );
      },
    );
  }

  void _openReportDialog() {
    showDialog(
      context: context,
      builder: (context) => ReportDialog(
        historyData: _historyData,
        isDark: Theme.of(context).brightness == Brightness.dark,
        initialComponents: _reportComponents,
        onRequestChartSelection: (index, isStart) {
          setState(() {
            _reportComponents = _reportComponents; 
            _isSelectingForReport = true;
            _reportComponentIndex = index;
            _isSelectingReportStart = isStart;
            _selectedPeriod = PeriodType.custom; 
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('📍 Cliquez sur le graphique pour définir le ${isStart ? "Début" : "Fin"} de l\'appareil ${index + 1}'),
              duration: const Duration(seconds: 4),
              backgroundColor: Colors.orange,
            ),
          );
        },
      ),
    ).then((result) {
      if (result != null && result is List<ReportComponent>) {
        setState(() => _reportComponents = result);
      }
    });
  }

  @override
  void dispose() {
    _rtSubscription?.cancel();
    _historySubscription?.cancel();
    _timeSubscription?.cancel();
    _limitSubscription?.cancel();
    super.dispose();
  }

  double get _energieDepuisReset => _energieBaseReset == -1.0 ? 0.0 : (_energieTotale - _energieBaseReset).clamp(0.0, double.infinity);
  
  double get _energieJournaliere {
    if (_historyData.isEmpty) return 0.0;
    double totalKwh = 0.0;
    for (int i = 1; i < _historyData.length; i++) {
      DateTime currTime = _historyData[i]['time'];
      if (currTime.year == _selectedDate.year && currTime.month == _selectedDate.month && currTime.day == _selectedDate.day) {
        double hoursDiff = currTime.difference(_historyData[i-1]['time']).inSeconds / 3600.0;
        if (hoursDiff > 0 && hoursDiff <= (10.0 / 60.0)) totalKwh += (_historyData[i]['p'] * hoursDiff) / 1000.0;
      }
    }
    return totalKwh;
  }

  double get _energieJournaliereProd {
    if (_historyData.isEmpty) return 0.0;
    double totalKwh = 0.0;
    for (int i = 1; i < _historyData.length; i++) {
      DateTime currTime = _historyData[i]['time'];
      if (currTime.year == _selectedDate.year && currTime.month == _selectedDate.month && currTime.day == _selectedDate.day) {
        double hoursDiff = currTime.difference(_historyData[i-1]['time']).inSeconds / 3600.0;
        if (hoursDiff > 0 && hoursDiff <= (10.0 / 60.0)) totalKwh += (_historyData[i]['p_prod'] * hoursDiff) / 1000.0;
      }
    }
    return totalKwh;
  }

  double get _energieCustom {
    if (_historyData.isEmpty) return 0.0;
    double totalKwh = 0.0;
    for (int i = 1; i < _historyData.length; i++) {
      DateTime currTime = _historyData[i]['time'];
      if (currTime.isAfter(_customStart) && currTime.isBefore(_customEnd)) {
        double hoursDiff = currTime.difference(_historyData[i-1]['time']).inSeconds / 3600.0;
        if (hoursDiff > 0 && hoursDiff <= (10.0 / 60.0)) {
          totalKwh += (_historyData[i]['p'] * hoursDiff) / 1000.0;
        }
      }
    }
    return totalKwh;
  }

  double get _energieMensuelle {
    if (_historyData.isEmpty) return 0.0;
    double totalKwh = 0.0;
    for (int i = 1; i < _historyData.length; i++) {
      DateTime currTime = _historyData[i]['time'];
      if (currTime.year == _selectedDate.year && currTime.month == _selectedDate.month) {
        double hoursDiff = currTime.difference(_historyData[i-1]['time']).inSeconds / 3600.0;
        if (hoursDiff > 0 && hoursDiff <= (10.0 / 60.0)) {
          totalKwh += (_historyData[i]['p'] * hoursDiff) / 1000.0;
        }
      }
    }
    return totalKwh;
  }

  double get _customDurationHours {
    double hours = _customEnd.difference(_customStart).inMinutes / 60.0;
    return hours > 0.01 ? hours : 1.0; 
  }

  double get _customDurationDays {
    double days = _customEnd.difference(_customStart).inHours / 24.0;
    return days > 0.01 ? days : 1.0; 
  }

  double get _moyenneHeureCustom => _energieCustom / _customDurationHours;
  double get _moyenneJourCustom => _energieCustom / _customDurationDays;

  void _checkLimits() {
    if (_limitAlertTriggered) return;

    bool dailyExceeded = _dailyLimit > 0 && _energieJournaliere > _dailyLimit;
    bool monthlyExceeded = _monthlyLimit > 0 && _energieMensuelle > _monthlyLimit;

    if (dailyExceeded || monthlyExceeded) {
      _limitAlertTriggered = true;
      String message = "";
      if (dailyExceeded) message = "Alerte : Limite journalière dépassée ! (${_energieJournaliere.toStringAsFixed(2)} / ${_dailyLimit} kWh)";
      if (monthlyExceeded) message = "Alerte : Limite mensuelle dépassée ! (${_energieMensuelle.toStringAsFixed(2)} / ${_monthlyLimit} kWh)";

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28), const SizedBox(width: 12), Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)))]),
            backgroundColor: Colors.red, duration: const Duration(seconds: 8), behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  DateTime _getStartTime() {
    DateTime now = DateTime.now();
    if (_hourRange == 24) return DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 0, 0, 0);
    return now.subtract(Duration(hours: _hourRange));
  }

  // ✅ PRÉPARATION DES DONNÉES POUR LE GRAPHIQUE (Inchangé, mais isolé dans le widget)
  List<FlSpot> get _chartSpotsConso {
    if (_historyData.isEmpty) return [];
    if (_selectedPeriod == PeriodType.custom) {
      return _historyData.map((data) {
        final time = data['time'] as DateTime;
        double xValue = time.millisecondsSinceEpoch.toDouble() / 3600000.0;
        double yValue = 0.0;
        if (_selectedMetric == MetricType.puissance) yValue = data['p'];
        if (_selectedMetric == MetricType.tension) yValue = data['v'];
        if (_selectedMetric == MetricType.courant) yValue = data['i'];
        return FlSpot(xValue, yValue);
      }).toList();
    }

    DateTime now = DateTime.now();
    DateTime startTime = _getStartTime();
    bool isToday = _selectedDate.day == now.day && _selectedDate.month == now.month && _selectedDate.year == now.year;

    return _historyData.where((data) {
      DateTime date = data['time'];
      bool isSameDay = date.year == _selectedDate.year && date.month == _selectedDate.month && date.day == _selectedDate.day;
      if (isSameDay && isToday && _hourRange < 24) return date.isAfter(startTime);
      return isSameDay;
    }).map((data) {
      final time = data['time'] as DateTime;
      double xValue = time.hour + (time.minute / 60.0);
      double yValue = 0.0;
      if (_selectedMetric == MetricType.puissance) yValue = data['p'];
      if (_selectedMetric == MetricType.tension) yValue = data['v'];
      if (_selectedMetric == MetricType.courant) yValue = data['i'];
      return FlSpot(xValue, yValue);
    }).toList();
  }

  List<FlSpot> get _chartSpotsProd {
    if (_historyData.isEmpty || _selectedMetric != MetricType.puissance) return [];
    if (_selectedPeriod == PeriodType.custom) {
      return _historyData.map((data) {
        final time = data['time'] as DateTime;
        double xValue = time.millisecondsSinceEpoch.toDouble() / 3600000.0;
        return FlSpot(xValue, data['p_prod']);
      }).toList();
    }

    DateTime now = DateTime.now();
    bool isToday = _selectedDate.day == now.day && _selectedDate.month == now.month && _selectedDate.year == now.year;

    return _historyData.where((data) {
      DateTime date = data['time'];
      bool isSameDay = date.year == _selectedDate.year && date.month == _selectedDate.month && date.day == _selectedDate.day;
      if (isSameDay && isToday && _hourRange < 24) return date.isAfter(_getStartTime());
      return isSameDay;
    }).map((data) {
      final time = data['time'] as DateTime;
      double xValue = time.hour + (time.minute / 60.0);
      return FlSpot(xValue, data['p_prod']);
    }).toList();
  }

  List<Map<String, dynamic>> _getBarData() {
    if (_historyData.isEmpty) return [];
    Map<int, Map<String, double>> aggregated = {};
    for (int i = 1; i < _historyData.length; i++) {
      DateTime prevTime = _historyData[i - 1]['time'];
      DateTime currTime = _historyData[i]['time'];
      double hoursDiff = currTime.difference(prevTime).inSeconds / 3600.0;
      if (hoursDiff > 0 && hoursDiff <= (10.0 / 60.0)) {
        double energyConsoKwh = (_historyData[i]['p'] * hoursDiff) / 1000.0;
        double energyProdKwh = (_historyData[i]['p_prod'] * hoursDiff) / 1000.0;
        int key = 0;
        if (_selectedPeriod == PeriodType.month) key = currTime.day;
        else if (_selectedPeriod == PeriodType.year) key = currTime.month;
        else if (_selectedPeriod == PeriodType.total) key = currTime.year;
        bool include = false;
        if (_selectedPeriod == PeriodType.month) include = (currTime.year == _selectedDate.year && currTime.month == _selectedDate.month);
        else if (_selectedPeriod == PeriodType.year) include = (currTime.year == _selectedDate.year);
        else if (_selectedPeriod == PeriodType.total) include = true;
        if (include) {
          if (!aggregated.containsKey(key)) aggregated[key] = {'conso': 0.0, 'prod': 0.0};
          aggregated[key]!['conso'] = aggregated[key]!['conso']! + energyConsoKwh;
          aggregated[key]!['prod'] = aggregated[key]!['prod']! + energyProdKwh;
        }
      }
    }
    List<Map<String, dynamic>> groups = [];
    int startX = 1, endX = 31;
    if (_selectedPeriod == PeriodType.year) endX = 12;
    else if (_selectedPeriod == PeriodType.total) {
      int minYear = 9999, maxYear = 0;
      aggregated.forEach((key, value) { if (key < minYear) minYear = key; if (key > maxYear) maxYear = key; });
      startX = minYear == 9999 ? DateTime.now().year : minYear;
      endX = maxYear == 0 ? DateTime.now().year : maxYear;
    }
    for (int i = startX; i <= endX; i++) {
      groups.add({'x': i, 'conso': aggregated[i]?['conso'] ?? 0.0, 'prod': aggregated[i]?['prod'] ?? 0.0});
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    bool isAlert = _puissance > _alertThreshold;
    bool isOnline = _isEspOnline;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final borderColor = Theme.of(context).dividerColor;
    final textColor = isDark ? Colors.white : Colors.black87;

    String resetSessionStr = _resetSessionTime != null 
      ? DateFormat('dd/MM à HH:mm').format(DateTime.fromMillisecondsSinceEpoch(_resetSessionTime!)) 
      : "Non défini";
      
    String pzemResetStr = _pzemResetTime != null 
      ? DateFormat('dd/MM à HH:mm').format(DateTime.fromMillisecondsSinceEpoch(_pzemResetTime!)) 
      : "Jamais";

    return Scaffold(
            appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min, // ✅ Évite que le titre prenne trop de place
          children: [
            Image.asset('assets/logo.png', height: 32, fit: BoxFit.contain),
            const SizedBox(width: 12),
            Text('Smart Meter', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: textColor)),
            // ✅ Le voyant vert a été supprimé
          ],
        ),
        backgroundColor: cardColor,
        elevation: 0,
        actions: [
          // 1. Bouton VE (Toujours visible)
          IconButton(
            icon: const Icon(Icons.electric_car, color: Colors.green),
            tooltip: 'Optimisation Charge VE',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => EvChargingDialog(historyData: _historyData, isDark: isDark),
              );
            },
          ),

          // 2. Bouton Limite
          IconButton(
            icon: Icon(Icons.speed, color: (_dailyLimit > 0 || _monthlyLimit > 0) ? Colors.orange : Colors.grey),
            tooltip: 'Définir les limites',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => LimitDialog(currentDailyLimit: _dailyLimit, currentMonthlyLimit: _monthlyLimit, isDark: isDark),
              );
            },
          ),

          // 3. Menu des 3 points (PDF, STEG, Paramètres, Reset)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.grey),
            tooltip: 'Outils et Paramètres',
            color: cardColor,
            onSelected: (value) {
              if (value == 'pdf') {
                _openReportDialog();
              } else if (value == 'steg') {
                showDialog(
                  context: context,
                  builder: (context) => StegEstimateDialog(historyData: _historyData, isDark: isDark),
                );
              } else if (value == 'settings') {
                if (_isAdmin) {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => SettingsScreen(isDark: isDark)));
                } else {
                  _loginAsAdmin();
                }
              } else if (value == 'reset') {
                _resetData(); // ✅ Déplacé ici
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'pdf',
                child: Row(children: [const Icon(Icons.picture_as_pdf, color: Colors.redAccent, size: 20), const SizedBox(width: 12), Text('Rapport PDF', style: TextStyle(color: textColor))]),
              ),
              PopupMenuItem<String>(
                value: 'steg',
                child: Row(children: [const Icon(Icons.receipt_long, color: Colors.blueAccent, size: 20), const SizedBox(width: 12), Text('Estimation STEG', style: TextStyle(color: textColor))]),
              ),
              PopupMenuItem<String>(
                value: 'reset',
                child: Row(children: [const Icon(Icons.refresh, color: Color(0xFFE67E22), size: 20), const SizedBox(width: 12), Text('Reset Session', style: TextStyle(color: textColor))]),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'settings',
                child: Row(children: [Icon(_isAdmin ? Icons.settings : Icons.lock_outline, color: _isAdmin ? Colors.blue : Colors.grey, size: 20), const SizedBox(width: 12), Text(_isAdmin ? 'Paramètres Admin' : 'Connexion Admin', style: TextStyle(color: textColor))]),
              ),
            ],
          ),

          // 4. Bouton Thème
          IconButton(icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode, color: Colors.orange), onPressed: widget.onToggleTheme),
          
          // ✅ Le bouton Reset a été retiré d'ici
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (!isOnline)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), border: Border.all(color: Colors.red.withOpacity(0.5)), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [const Icon(Icons.wifi_off, color: Colors.red), const SizedBox(width: 12), Expanded(child: Text(_lastSeenTime == null ? "ESP jamais connecté" : "ESP Hors ligne. Dernière connexion : ${DateFormat('dd/MM à HH:mm').format(_lastSeenTime!)}", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)))]),
              ),

            LayoutBuilder(
              builder: (context, constraints) {
                bool isMobile = constraints.maxWidth < 900;
                
                Widget gaugeWidget = Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: isAlert ? Colors.red : borderColor, width: isAlert ? 2 : 1)),
                  child: Column(
                    children: [
                      Text('Puissance Actuelle', style: TextStyle(color: Colors.grey, fontSize: 14)),
                      const SizedBox(height: 12),
                      SizedBox(height: 120, width: 220, child: CustomPaint(painter: GaugePainter(value: _puissance, maxValue: _alertThreshold * 1.5, alertThreshold: _alertThreshold, bgColor: borderColor, needleColor: textColor), child: Center(child: Padding(padding: const EdgeInsets.only(top: 40), child: Text('${_puissance.toStringAsFixed(0)} W', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: isAlert ? Colors.red : const Color(0xFFE67E22))))))),
                    ],
                  ),
                );

                List<Widget> cards = [];

                if (_selectedPeriod == PeriodType.custom) {
                  cards.add(_buildMetricCard('Conso. Période', '${_energieCustom.toStringAsFixed(3)} kWh', Icons.date_range, Colors.purpleAccent, isMobile));
                  cards.add(_buildMetricCard('Moy. / Heure', '${_moyenneHeureCustom.toStringAsFixed(3)} kWh/h', Icons.av_timer, Colors.pinkAccent, isMobile));
                  cards.add(_buildMetricCard('Moy. / Jour', '${_moyenneJourCustom.toStringAsFixed(3)} kWh/j', Icons.calendar_month, Colors.lightBlueAccent, isMobile));
                  
                  cards.add(_buildMetricCard('Énergie (Reset)', '${_energieDepuisReset.toStringAsFixed(3)} kWh', Icons.restart_alt, const Color(0xFF3498DB), isMobile, subtitle: resetSessionStr));
                } else {
                  cards.add(_buildMetricCard('Conso. Jour', '${_energieJournaliere.toStringAsFixed(3)} kWh', Icons.electric_meter, const Color(0xFF2ECC71), isMobile));
                  cards.add(_buildMetricCard('Prod. Jour', '${_energieJournaliereProd.toStringAsFixed(3)} kWh', Icons.solar_power, const Color(0xFF1ABC9C), isMobile));
                  
                  cards.add(_buildMetricCard('Énergie (Reset)', '${_energieDepuisReset.toStringAsFixed(3)} kWh', Icons.restart_alt, const Color(0xFF3498DB), isMobile, subtitle: resetSessionStr));
                }

                cards.add(_buildMetricCard('Total Compteur', '${_energieTotale.toStringAsFixed(3)} kWh', Icons.battery_charging_full, const Color(0xFFE67E22), isMobile, subtitle: pzemResetStr));

                Widget metricsWidget = Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: cards);

                if (isMobile) return Column(children: [gaugeWidget, const SizedBox(height: 16), metricsWidget]);
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 1, child: gaugeWidget), const SizedBox(width: 16), Expanded(flex: 3, child: metricsWidget)]);
              },
            ),
            
            const SizedBox(height: 16),

            Container(
              decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTopControls(isDark, borderColor),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_selectedMetric == MetricType.puissance || _selectedPeriod != PeriodType.day) ...[
                        _buildLegendItem('Consommation', const Color(0xFFF5B041)),
                        const SizedBox(width: 24),
                        _buildLegendItem('Production', const Color(0xFF1ABC9C)),
                      ] else ...[
                        _buildLegendItem(_chartLabel, _chartColor),
                      ]
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 300,
                    child: _historyData.isEmpty 
                        ? const Center(child: Text('Aucune donnée disponible...', style: TextStyle(color: Colors.grey)))
                        : DashboardChart(
                            spotsConso: _chartSpotsConso,
                            spotsProd: _chartSpotsProd,
                            barData: _getBarData(),
                            selectedMetric: _selectedMetric,
                            selectedPeriod: _selectedPeriod,
                            customStart: _customStart,
                            customEnd: _customEnd,
                            tempStartSelection: _tempStartSelection,
                            selectedDate: _selectedDate,
                            hourRange: _hourRange,
                            isDark: isDark,
                            onGraphTouch: _handleGraphTouch,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color get _chartColor {
    if (_selectedPeriod != PeriodType.day) return const Color(0xFFF5B041);
    switch (_selectedMetric) {
      case MetricType.puissance: return const Color(0xFFF5B041);
      case MetricType.tension: return const Color(0xFF3498DB);
      case MetricType.courant: return const Color(0xFFE74C3C);
      case MetricType.status: return Colors.green;
    }
  }

  String get _chartLabel => _selectedPeriod != PeriodType.day ? 'Énergie (kWh)' : (_selectedMetric == MetricType.puissance ? 'Puissance' : (_selectedMetric == MetricType.tension ? 'Tension' : (_selectedMetric == MetricType.courant ? 'Courant' : 'ESP')));

  Widget _buildLegendItem(String label, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: color)), const SizedBox(width: 8), Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))]);
  }

  Widget _buildTopControls(bool isDark, Color borderColor) {
    final textColor = isDark ? Colors.white : Colors.black87;

    Widget tabsWidget = Container(
      decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _buildTabButton('Day', PeriodType.day), 
        _buildTabButton('Month', PeriodType.month), 
        _buildTabButton('Year', PeriodType.year), 
        _buildTabButton('Total', PeriodType.total),
        _buildTabButton('Custom', PeriodType.custom),
      ]),
    );

    Widget dateWidget;
    if (_selectedPeriod == PeriodType.custom) {
      dateWidget = Row(mainAxisSize: MainAxisSize.min, children: [
        Text("Début : ${DateFormat('dd/MM HH:mm').format(_customStart)}", style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(width: 16),
        Text("Fin : ${DateFormat('dd/MM HH:mm').format(_customEnd)}", style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold)),
      ]);
    } else {
      String dateText = "";
      if (_selectedPeriod == PeriodType.day) dateText = DateFormat('yyyy-MM-dd').format(_selectedDate);
      else if (_selectedPeriod == PeriodType.month) dateText = DateFormat('yyyy-MM').format(_selectedDate);
      else if (_selectedPeriod == PeriodType.year) dateText = DateFormat('yyyy').format(_selectedDate);
      else dateText = "Tout";

      dateWidget = Row(mainAxisSize: MainAxisSize.min, children: [
        if (_selectedPeriod != PeriodType.total) IconButton(icon: const Icon(Icons.chevron_left, color: Colors.grey, size: 20), onPressed: () => _changeDate(-1), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
        const SizedBox(width: 8), Text(dateText, style: TextStyle(fontSize: 14, color: textColor, fontWeight: FontWeight.w500)), const SizedBox(width: 8),
        if (_selectedPeriod != PeriodType.total) IconButton(icon: const Icon(Icons.chevron_right, color: Colors.grey, size: 20), onPressed: () => _changeDate(1), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
      ]);
    }

    Widget actionsWidget = Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
      if (_selectedPeriod == PeriodType.day)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)),
          child: DropdownButtonHideUnderline(child: DropdownButton<int>(
            value: _hourRange, dropdownColor: Theme.of(context).cardColor, icon: const Icon(Icons.arrow_drop_down, color: Colors.grey), style: TextStyle(color: textColor, fontSize: 13),
            onChanged: (val) { if (val != null) setState(() => _hourRange = val); },
            items: const [DropdownMenuItem(value: 1, child: Text('1 Heure')), DropdownMenuItem(value: 6, child: Text('6 Heures')), DropdownMenuItem(value: 12, child: Text('12 Heures')), DropdownMenuItem(value: 24, child: Text('24 Heures'))],
          )),
        ),
      if (_selectedPeriod == PeriodType.day || _selectedPeriod == PeriodType.custom)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)),
          child: DropdownButtonHideUnderline(child: DropdownButton<MetricType>(
            value: _selectedMetric, dropdownColor: Theme.of(context).cardColor, icon: const Icon(Icons.arrow_drop_down, color: Colors.grey), style: TextStyle(color: textColor, fontSize: 13),
            onChanged: (val) { if (val != null) setState(() => _selectedMetric = val); },
            items: const [DropdownMenuItem(value: MetricType.puissance, child: Text('Puissance (W)')), DropdownMenuItem(value: MetricType.tension, child: Text('Tension (V)')), DropdownMenuItem(value: MetricType.courant, child: Text('Courant (A)')), DropdownMenuItem(value: MetricType.status, child: Text('Statut ESP (Connexion)'))],
          )),
        )
      else
        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.grey.shade200, border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)), child: Text('Énergie (kWh)', style: TextStyle(color: Colors.grey, fontSize: 13))),
    ]);

    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 900) return Column(children: [Center(child: tabsWidget), const SizedBox(height: 12), Center(child: dateWidget), const SizedBox(height: 12), Center(child: actionsWidget)]);
      return Wrap(spacing: 16, runSpacing: 12, alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [tabsWidget, dateWidget, actionsWidget]);
    });
  }

  Widget _buildTabButton(String text, PeriodType period) {
    bool isActive = _selectedPeriod == period;
    return GestureDetector(
      onTap: () => setState(() => _selectedPeriod = period),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: isActive ? const Color(0xFFE67E22) : Colors.transparent, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(color: isActive ? Colors.white : Colors.grey, fontSize: 13, fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color, bool isMobile, {String? subtitle}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: isMobile ? (MediaQuery.of(context).size.width - 44) / 2 : 200,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(12), border: Border(left: BorderSide(color: color, width: 4))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, 
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [Icon(icon, color: color, size: 18), const SizedBox(width: 8), Expanded(child: Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis))]),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: isDark ? Colors.white : Colors.black87)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text("Le: $subtitle", style: const TextStyle(color: Colors.grey, fontSize: 10)),
          ]
        ],
      ),
    );
  }
}