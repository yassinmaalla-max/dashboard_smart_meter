import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class SettingsScreen extends StatefulWidget {
  final bool isDark;
  const SettingsScreen({super.key, required this.isDark});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  
  void _sendResetCommand(bool clearGraph) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmation'),
        content: Text(clearGraph 
          ? 'Voulez-vous effacer la mémoire du PZEM ET vider le graphique ? Cette action est irréversible.' 
          : 'Voulez-vous effacer uniquement la mémoire interne du PZEM (Total Compteur) ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('Confirmer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseDatabase.instance.ref('commandes/reset_pzem').set(true);
        
        // ✅ On remet la base à zéro
        await FirebaseDatabase.instance.ref('compteur/reset_base').set(0);
        
        // ✅ NOUVEAU : On enregistre l'heure du reset PZEM
        await FirebaseDatabase.instance.ref('compteur/pzem_reset_time').set(ServerValue.timestamp);
        
        if (clearGraph) await FirebaseDatabase.instance.ref('historique/live').remove();
        
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Ordre de reset envoyé !'), backgroundColor: Colors.green));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Erreur : $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _syncOfflineData() async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      final rawRef = FirebaseDatabase.instance.ref('offline_raw/data');
      final snapshot = await rawRef.get();
      if (!snapshot.exists || snapshot.value == null) {
        if (mounted) Navigator.pop(context);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucune donnée hors-ligne à traiter.')));
        return;
      }

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

      if (mounted) Navigator.pop(context);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Données hors-ligne synchronisées !'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Erreur : $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final textColor = widget.isDark ? Colors.white : Colors.black87;

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres Admin'), backgroundColor: cardColor, iconTheme: IconThemeData(color: textColor)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSettingCard(
            title: "Compteur PZEM",
            icon: Icons.restart_alt,
            color: Colors.orange,
            children: [
              ListTile(
                title: Text('Reset PZEM uniquement', style: TextStyle(color: textColor)),
                subtitle: const Text('Remet à zéro la case "Total Compteur"'),
                onTap: () => _sendResetCommand(false),
              ),
              const Divider(),
              ListTile(
                title: const Text('Reset PZEM + Graphique', style: TextStyle(color: Colors.red)),
                subtitle: const Text('Efface le compteur ET tout l\'historique Firebase'),
                onTap: () => _sendResetCommand(true),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSettingCard(
            title: "Données Hors-ligne",
            icon: Icons.sync,
            color: Colors.blue,
            children: [
              ListTile(
                title: Text('Synchroniser les données', style: TextStyle(color: textColor)),
                subtitle: const Text('Traiter le fichier offline de l\'ESP'),
                trailing: const Icon(Icons.sync),
                onTap: _syncOfflineData,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingCard({required String title, required IconData icon, required Color color, required List<Widget> children}) {
    return Card(
      elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(children: [Icon(icon, color: color), const SizedBox(width: 8), Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color))]),
          ),
          ...children,
        ],
      ),
    );
  }
}