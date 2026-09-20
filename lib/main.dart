import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'bridge_js.dart';
import 'downloads.dart';

/// Página inicial do painel WLVD.
///
/// `panel.worldlabourvalues.org` redireciona (302) para este domínio
/// canônico, que já responde 200 diretamente.
const String kHomeUrl = 'https://worldlabourvalues.org';

const List<String> _allowedHosts = ['worldlabourvalues.org'];

/// Decide se uma URL pertence ao painel (mesmo domínio ou subdomínio).
bool isWlvdUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return _allowedHosts.any(
    (host) => uri.host == host || uri.host.endsWith('.$host'),
  );
}

bool _isNetworkError(WebResourceErrorType? type) {
  switch (type) {
    case WebResourceErrorType.hostLookup:
    case WebResourceErrorType.connect:
    case WebResourceErrorType.timeout:
    case WebResourceErrorType.failedSslHandshake:
    case WebResourceErrorType.io:
      return true;
    default:
      return false;
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  runApp(const WlvdApp());
}

class WlvdApp extends StatelessWidget {
  const WlvdApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WLVD',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.red,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const PanelWebView(),
    );
  }
}

class PanelWebView extends StatefulWidget {
  const PanelWebView({Key? key}) : super(key: key);

  @override
  State<PanelWebView> createState() => _PanelWebViewState();
}

class _PanelWebViewState extends State<PanelWebView> {
  WebViewController? _controller;
  bool _loading = true;
  bool _hasError = false;
  bool _finishedOnce = false;

  bool _downloading = false;
  String _downloadName = '';
  int _chunksReceived = 0;
  double? _downloadProgress;
  final StringBuffer _chunkBuffer = StringBuffer();

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    await _controller?.reload();
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Sem navegador externo disponível; mantém a navegação atual.
    }
  }

  Future<String> _currentUrl() async {
    final url = await _controller?.currentUrl();
    return url ?? kHomeUrl;
  }

  void _toast(String message, {VoidCallback? onOpenDownloads}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: onOpenDownloads == null
              ? null
              : SnackBarAction(
                  label: 'ABRIR',
                  onPressed: onOpenDownloads,
                ),
        ),
      );
  }

  Future<void> _sharePage() async {
    final url = await _currentUrl();
    await Share.share(
      url,
      subject: 'WLVD — World Labour Values Database',
    );
  }

  void _openDownloadsPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const DownloadsPage()),
    );
  }

  void _showMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Meus downloads'),
              subtitle: const Text('Planilhas baixadas do painel'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openDownloadsPage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Compartilhar página'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _sharePage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Abrir no navegador'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _openExternal(await _currentUrl());
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Recarregar painel'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _reload();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _handleBridgeMessage(JavascriptMessage message) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(message.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (data['type'] as String?) {
      case 'pullrefresh':
        _reload();
        break;
      case 'download':
        _startDownload((data['name'] as String?) ?? 'download');
        break;
      case 'chunk':
        _receiveChunk(data);
        break;
      case 'done':
        _finishDownload((data['name'] as String?) ?? _downloadName);
        break;
      case 'error':
        _cancelDownload(
          (data['message'] as String?) ?? 'Falha no download.',
        );
        break;
      case 'busy':
        _toast('Aguarde: já há um download em andamento.');
        break;
    }
  }

  void _startDownload(String name) {
    setState(() {
      _downloading = true;
      _downloadName = name;
      _downloadProgress = null;
      _chunksReceived = 0;
      _chunkBuffer.clear();
    });
  }

  void _receiveChunk(Map<String, dynamic> data) {
    if (!_downloading) return;
    _chunkBuffer.write((data['data'] as String?) ?? '');
    final total = (data['total'] as num?)?.toInt() ?? 0;
    final seq = (data['seq'] as num?)?.toInt() ?? _chunksReceived;
    if (total > 0) {
      _downloadProgress = (seq + 1) / total;
    }
    _chunksReceived = seq + 1;
    if (mounted) setState(() {});
  }

  Future<void> _finishDownload(String name) async {
    if (!_downloading) return;
    final base64 = _chunkBuffer.toString();
    _chunkBuffer.clear();
    setState(() {
      _downloading = false;
      _downloadProgress = null;
    });
    try {
      final bytes = base64Decode(base64);
      final file = await DownloadStore.save(name, bytes);
      if (!mounted) return;
      _toast(
        'Salvo: ${file.uri.pathSegments.last}',
        onOpenDownloads: _openDownloadsPage,
      );
    } catch (_) {
      if (!mounted) return;
      _toast('Falha ao salvar o arquivo baixado.');
    }
  }

  void _cancelDownload(String message) {
    if (!_downloading) return;
    _chunkBuffer.clear();
    setState(() {
      _downloading = false;
      _downloadProgress = null;
    });
    _toast('Download falhou: $message');
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        final controller = _controller;
        if (controller != null && await controller.canGoBack()) {
          await controller.goBack();
          return false;
        }
        return true;
      },
      child: Scaffold(
        floatingActionButton: _hasError
            ? null
            : Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom,
                ),
                child: FloatingActionButton(
                  onPressed: _showMenu,
                  tooltip: 'Downloads e opções',
                  backgroundColor: const Color(0xFF2A1F1E),
                  child: const Icon(Icons.download),
                ),
              ),
        body: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                child: WebView(
                  initialUrl: kHomeUrl,
                  javascriptMode: JavascriptMode.unrestricted,
                  gestureNavigationEnabled: true,
                  javascriptChannels: <JavascriptChannel>{
                    JavascriptChannel(
                      name: 'WLVDNative',
                      onMessageReceived: _handleBridgeMessage,
                    ),
                  },
                  onWebViewCreated: (controller) {
                    _controller = controller;
                  },
                  navigationDelegate: (request) {
                    if (isWlvdUrl(request.url)) {
                      return NavigationDecision.navigate;
                    }
                    _openExternal(request.url);
                    return NavigationDecision.prevent;
                  },
                  onPageStarted: (_) {
                    if (!_loading || _hasError) {
                      setState(() {
                        _loading = true;
                        _hasError = false;
                      });
                    }
                  },
                  onPageFinished: (_) {
                    final controller = _controller;
                    if (controller != null) {
                      unawaited(controller.runJavascript(kBridgeJs));
                    }
                    setState(() {
                      _loading = false;
                      _finishedOnce = true;
                    });
                  },
                  onWebResourceError: (error) {
                    if (!_finishedOnce && _isNetworkError(error.errorType)) {
                      setState(() {
                        _loading = false;
                        _hasError = true;
                      });
                    }
                  },
                ),
              ),
            ),
            if (_loading || _downloading)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_loading)
                        const LinearProgressIndicator(minHeight: 3),
                      if (_downloading) _DownloadBanner(
                        name: _downloadName,
                        progress: _downloadProgress,
                      ),
                    ],
                  ),
                ),
              ),
            if (_hasError)
              Positioned.fill(
                child: _ErrorView(onRetry: _reload),
              ),
          ],
        ),
      ),
    );
  }
}

class _DownloadBanner extends StatelessWidget {
  const _DownloadBanner({required this.name, required this.progress});

  final String name;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final preparing = progress == null;
    final label = preparing
        ? 'Preparando download…'
        : 'Baixando ${name.isEmpty ? 'arquivo' : name} '
            '(${(progress! * 100).round()}%)';
    return Material(
      color: const Color(0xF02A1F1E),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              minHeight: 3,
              value: progress,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFDD695)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 56, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Não foi possível carregar o painel.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'Verifique sua conexão com a internet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
