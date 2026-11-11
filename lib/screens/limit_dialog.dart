import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class LimitDialog extends StatefulWidget {
  final double currentDailyLimit;
  final double currentMonthlyLimit;
  final bool isDark;

  const LimitDialog({
    super.key, 
    required this.currentDailyLimit, 
    required this.currentMonthlyLimit, 
    required this.isDark
  });

  @override
  State<LimitDialog> createState() => _LimitDialogState();
}

class _LimitDialogState extends State<LimitDialog> {
  late double _dailyLimit;
  late double _monthlyLimit;
  late TextEditingController _dailyController;
  late TextEditingController _monthlyController;

  @override
  void initState() {
    super.initState();
    _dailyLimit = widget.currentDailyLimit;
    _monthlyLimit = widget.currentMonthlyLimit;
    _dailyController = TextEditingController(text: _dailyLimit.toStringAsFixed(1));
    _monthlyController = TextEditingController(text: _monthlyLimit.toStringAsFixed(1));
  }

  @override
  void dispose() {
    _dailyController.dispose();
    _monthlyController.dispose();
    super.dispose();
  }

  void _saveLimits() async {
    await FirebaseDatabase.instance.ref('config/limits').update({
      'daily': _dailyLimit,
      'monthly': _monthlyLimit,
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final cardColor = widget.isDark ? const Color(0xFF1A1D24) : Colors.white;

    return AlertDialog(
      backgroundColor: cardColor,
      title: Text('Définir les limites', style: TextStyle(color: textColor)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ SECTION LIMITE JOURNALIÈRE
            Text('Limite Journalière (kWh)', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _dailyLimit,
                    min: 0,
                    max: 50,
                    divisions: 100,
                    label: '${_dailyLimit.toStringAsFixed(1)} kWh',
                    onChanged: (val) {
                      setState(() {
                        _dailyLimit = val;
                        _dailyController.text = val.toStringAsFixed(1);
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: _dailyController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: textColor),
                    decoration: const InputDecoration(isDense: true),
                    onChanged: (val) {
                      double? parsed = double.tryParse(val);
                      if (parsed != null && parsed >= 0 && parsed <= 50) {
                        setState(() => _dailyLimit = parsed);
                      }
                    },
                  ),
                ),
              ],
            ),
            const Divider(height: 30),

            // ✅ SECTION LIMITE MENSUELLE
            Text('Limite Mensuelle (kWh)', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _monthlyLimit,
                    min: 0,
                    max: 1000,
                    divisions: 100,
                    label: '${_monthlyLimit.toStringAsFixed(0)} kWh',
                    onChanged: (val) {
                      setState(() {
                        _monthlyLimit = val;
                        _monthlyController.text = val.toStringAsFixed(0);
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: _monthlyController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: textColor),
                    decoration: const InputDecoration(isDense: true),
                    onChanged: (val) {
                      double? parsed = double.tryParse(val);
                      if (parsed != null && parsed >= 0 && parsed <= 1000) {
                        setState(() => _monthlyLimit = parsed);
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE67E22)),
          onPressed: _saveLimits,
          child: const Text('Enregistrer', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}