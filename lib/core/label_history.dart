import 'package:flutter/material.dart';
import '../core/database.dart';

// Simple screen that lists every row currently saved in scanned_labelsTB
// and lets the user delete entries they don't want anymore. Reuses the
// existing DatabaseService/ScannedLabels model — no new tables or queries
// needed, just outPutLabels() (no filters = everything) and deleteLabel().
class LabelHistoryPage extends StatefulWidget {
  const LabelHistoryPage({super.key});

  @override
  State<LabelHistoryPage> createState() => _LabelHistoryPageState();
}

class _LabelHistoryPageState extends State<LabelHistoryPage> {
  final DatabaseService _dbService = DatabaseService();
  late Future<List<ScannedLabels>> _labelsFuture;

  @override
  void initState() {
    super.initState();
    _loadLabels();
  }

  // Kicks off a fresh query. Called from initState and again after any
  // delete so the list reflects the current DB state.
  void _loadLabels() {
    _labelsFuture = _dbService.outPutLabels();
  }

  Future<void> _confirmDelete(ScannedLabels label) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete entry"),
        content: Text("Remove '${label.text}' from the scan history?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed == true && label.id != null) {
      await _dbService.deleteLabel(label.id!);
      if (mounted) {
        setState(_loadLabels);
      }
    }
  }

  String _formatTime(String iso) {
    try {
      final DateTime dt = DateTime.parse(iso);
      final String date =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      final String time =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      return '$date  $time';
    } catch (_) {
      return iso; // fall back to raw string if parsing ever fails
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan History")),
      body: FutureBuilder<List<ScannedLabels>>(
        future: _labelsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error loading history: ${snapshot.error}"));
          }

          final List<ScannedLabels> labels = snapshot.data ?? [];
          if (labels.isEmpty) {
            return const Center(child: Text("No saved titles yet."));
          }

          return ListView.separated(
            itemCount: labels.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final ScannedLabels label = labels[index];
              return ListTile(
                title: Text(label.text.isEmpty ? "(untitled)" : label.text),
                subtitle: Text(_formatTime(label.times)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: "Delete",
                  onPressed: () => _confirmDelete(label),
                ),
              );
            },
          );
        },
      ),
    );
  }
}