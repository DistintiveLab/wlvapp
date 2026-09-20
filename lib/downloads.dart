import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Armazenamento local dos arquivos baixados do painel.
///
/// No Android usa o diretório externo específico do app
/// (`Android/data/<pkg>/files/downloads`), que não exige permissões e é
/// coberto pelo FileProvider do plugin `open_file`. Em outras plataformas
/// cai no diretório de documentos.
class DownloadStore {
  DownloadStore._();

  static Future<Directory> directory() async {
    final Directory base;
    final external = await getExternalStorageDirectory();
    if (external != null) {
      base = external;
    } else {
      base = await getApplicationDocumentsDirectory();
    }
    final dir = Directory('${base.path}/downloads');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Remove caracteres inválidos em nomes de arquivo e limita o tamanho.
  static String sanitizeFileName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
        .trim();
    final safe = cleaned.isEmpty ? 'download' : cleaned;
    return safe.length > 120 ? safe.substring(safe.length - 120) : safe;
  }

  static Future<File> save(String name, List<int> bytes) async {
    final dir = await directory();
    final safe = sanitizeFileName(name);
    var target = File('${dir.path}/$safe');
    if (await target.exists()) {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      target = File('${dir.path}/${stamp}_$safe');
    }
    return target.writeAsBytes(bytes, flush: true);
  }

  static Future<List<File>> list() async {
    final dir = await directory();
    final entries = await dir.list().toList();
    final files = entries.whereType<File>().toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} kB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String formatFileDate(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  final now = DateTime.now();
  final sameDay = date.year == now.year &&
      date.month == now.month &&
      date.day == now.day;
  if (sameDay) {
    return 'Hoje, ${two(date.hour)}:${two(date.minute)}';
  }
  return '${two(date.day)}/${two(date.month)}/${date.year} '
      '${two(date.hour)}:${two(date.minute)}';
}

IconData iconForFile(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
    return Icons.grid_on;
  }
  if (lower.endsWith('.csv')) {
    return Icons.table_chart;
  }
  if (lower.endsWith('.zip')) {
    return Icons.folder_zip;
  }
  return Icons.insert_drive_file;
}

/// Página com a lista de planilhas/dados baixados do painel.
class DownloadsPage extends StatefulWidget {
  const DownloadsPage({Key? key}) : super(key: key);

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  List<File>? _files;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final files = await DownloadStore.list();
      if (!mounted) return;
      setState(() {
        _files = files;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Não foi possível listar os arquivos.';
      });
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _open(File file) async {
    final result = await OpenFile.open(file.path);
    if (result.type != ResultType.done) {
      _toast('Não foi possível abrir: ${result.message}');
    }
  }

  Future<void> _share(File file) async {
    await Share.shareXFiles(
      [XFile(file.path, mimeType: _mimeTypeFor(file.path))],
    );
  }

  Future<void> _confirmDelete(File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir arquivo?'),
        content: Text(file.uri.pathSegments.last),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await file.delete();
      await _refresh();
    }
  }

  String _mimeTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.xls')) {
      return 'application/vnd.ms-excel';
    }
    if (lower.endsWith('.csv')) {
      return 'text/csv';
    }
    if (lower.endsWith('.zip')) {
      return 'application/zip';
    }
    return 'application/octet-stream';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus downloads'),
        backgroundColor: const Color(0xFF2A1F1E),
      ),
      body: SafeArea(top: false, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }

    final files = _files;
    if (files == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (files.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.download_done, size: 56, color: Colors.black38),
              SizedBox(height: 16),
              Text(
                'Nenhum arquivo baixado ainda.',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 8),
              Text(
                'Use a aba Download do painel para baixar planilhas; '
                'elas ficam guardadas aqui para acesso rápido, mesmo offline.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: files.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final file = files[index];
          final stat = file.statSync();
          return ListTile(
            leading: Icon(iconForFile(file.path), color: Colors.brown),
            title: Text(
              file.uri.pathSegments.last,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${formatFileSize(stat.size)} · ${formatFileDate(stat.modified)}',
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (action) {
                if (action == 'open') {
                  _open(file);
                } else if (action == 'share') {
                  _share(file);
                } else if (action == 'delete') {
                  _confirmDelete(file);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'open',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.open_in_new),
                    title: Text('Abrir com…'),
                  ),
                ),
                PopupMenuItem(
                  value: 'share',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.share),
                    title: Text('Compartilhar'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.delete),
                    title: Text('Excluir'),
                  ),
                ),
              ],
            ),
            onTap: () => _open(file),
          );
        },
      ),
    );
  }
}
