import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const A4AIApp());
}

class A4AIApp extends StatelessWidget {
  const A4AIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'a4ai',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.black),
      ),
      home: const MainHybridShell(),
    );
  }
}

class MainHybridShell extends StatefulWidget {
  const MainHybridShell({super.key});

  @override
  State<MainHybridShell> createState() => _MainHybridShellState();
}

class _MainHybridShellState extends State<MainHybridShell> {
  late final WebViewController _controller;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _isOffline = false;
  bool _isLoading = true;
  double _loadingProgress = 0.0;
  final String _initialUrl = 'https://www.a4ai.in';

  @override
  void initState() {
    super.initState();
    _initController();
    _initNetworkMonitoring();
  }

  void _initController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'BlobDownloader',
        onMessageReceived: (JavaScriptMessage message) {
          _handleBlobDownload(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (mounted) {
              setState(() {
                _loadingProgress = progress / 100.0;
              });
            }
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _isOffline = false;
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (error.errorCode == -2 ||
                error.errorCode == -6 ||
                error.errorCode == -8 ||
                error.errorType == WebResourceErrorType.hostLookup ||
                error.errorType == WebResourceErrorType.connect ||
                error.errorType == WebResourceErrorType.timeout) {
              if (mounted) {
                setState(() {
                  _isOffline = true;
                  _isLoading = false;
                });
              }
            }
          },
          onNavigationRequest: (NavigationRequest request) async {
            final uri = Uri.parse(request.url);
            final urlString = request.url.toLowerCase();

            // 1. Handle Blob URLs created by React/JS PDF/Doc generators
            if (urlString.startsWith('blob:')) {
              _processBlobUrl(request.url);
              return NavigationDecision.prevent;
            }

            // 2. Intercept direct file downloads (.pdf, .docx, etc.) and launch externally
            final isDocument = urlString.endsWith('.pdf') ||
                urlString.endsWith('.docx') ||
                urlString.endsWith('.doc') ||
                urlString.endsWith('.xlsx') ||
                urlString.endsWith('.csv') ||
                urlString.endsWith('.zip') ||
                uri.path.toLowerCase().endsWith('.pdf') ||
                uri.path.toLowerCase().endsWith('.docx');

            if (isDocument) {
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
                return NavigationDecision.prevent;
              }
            }

            // 3. Keep internal domain browsing inside the WebView
            if (uri.host.contains('a4ai.in') || uri.host.contains('supabase.co')) {
              return NavigationDecision.navigate;
            }

            // 4. Delegate external apps (WhatsApp, phone, mailto, etc.)
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      );

    if (_controller.platform is AndroidWebViewController) {
      final AndroidWebViewController androidController =
          _controller.platform as AndroidWebViewController;

      AndroidWebViewController.enableDebugging(true);
      androidController.setMediaPlaybackRequiresUserGesture(false);
      androidController.setOnShowFileSelector(_androidFilePicker);
    }

    _controller.loadRequest(Uri.parse(_initialUrl));
  }

  /// Converts a `blob:` URL inside the WebView into base64 data and passes it to Flutter
  void _processBlobUrl(String blobUrl) {
    final jsCode = '''
      (async function() {
        try {
          const response = await fetch('$blobUrl');
          const blob = await response.blob();
          const reader = new FileReader();
          reader.onloadend = function() {
            const base64data = reader.result;
            const mimeType = blob.type || 'application/pdf';
            window.BlobDownloader.postMessage(JSON.stringify({
              data: base64data,
              mimeType: mimeType,
              name: 'document_' + Date.now()
            }));
          };
          reader.readAsDataURL(blob);
        } catch (e) {
          console.error('Blob download error:', e);
        }
      })();
    ''';
    _controller.runJavaScript(jsCode);
  }

  /// Saves the base64 file to device storage and opens it
  Future<void> _handleBlobDownload(String message) async {
    try {
      final Map<String, dynamic> fileInfo = jsonDecode(message);
      final String rawData = fileInfo['data'] ?? '';
      final String mimeType = fileInfo['mimeType'] ?? 'application/pdf';
      final String baseName = fileInfo['name'] ?? 'download';

      if (rawData.isEmpty) return;

      // Extract raw base64 string after the comma (e.g. data:application/pdf;base64,...)
      final String base64Str = rawData.contains(',') ? rawData.split(',')[1] : rawData;
      final Uint8List bytes = base64Decode(base64Str);

      String extension = '.pdf';
      if (mimeType.contains('word') || mimeType.contains('docx')) {
        extension = '.docx';
      } else if (mimeType.contains('png')) {
        extension = '.png';
      } else if (mimeType.contains('jpeg') || mimeType.contains('jpg')) {
        extension = '.jpg';
      }

      final Directory tempDir = await getTemporaryDirectory();
      final File file = File('${tempDir.path}/$baseName$extension');
      await file.writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Document generated successfully! Opening..."),
            duration: Duration(seconds: 2),
          ),
        );
      }

      await OpenFile.open(file.path);
    } catch (e) {
      debugPrint('Error saving downloaded blob: $e');
    }
  }

  Future<List<String>> _androidFilePicker(FileSelectorParams params) async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf', 'docx'],
        allowMultiple: params.mode == FileSelectorMode.openMultiple,
      );

      if (result != null && result.files.isNotEmpty) {
        return result.files
            .where((f) => f.path != null)
            .map((f) => Uri.file(File(f.path!).path).toString())
            .toList();
      }
    } catch (e) {
      debugPrint('Error picking file in WebView: $e');
    }
    return [];
  }

  void _initNetworkMonitoring() {
    Connectivity().checkConnectivity().then((results) {
      if (results.contains(ConnectivityResult.none)) {
        if (mounted) {
          setState(() {
            _isOffline = true;
            _isLoading = false;
          });
        }
      }
    });

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final hasNoConnection = results.contains(ConnectivityResult.none);
      if (mounted) {
        if (hasNoConnection) {
          setState(() {
            _isOffline = true;
          });
        } else if (_isOffline) {
          _retryConnection();
        }
      }
    });
  }

  void _retryConnection() {
    setState(() {
      _isOffline = false;
      _isLoading = true;
      _loadingProgress = 0.1;
    });
    _controller.loadRequest(Uri.parse(_initialUrl));
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (_isOffline) {
          SystemNavigator.pop();
          return;
        }

        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),
              if (_isLoading && !_isOffline)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    value: _loadingProgress > 0 ? _loadingProgress : null,
                    backgroundColor: Colors.transparent,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.black),
                    minHeight: 2.5,
                  ),
                ),
              if (_isOffline)
                Positioned.fill(
                  child: A4AIOfflineView(onRetry: _retryConnection),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- BRANDED A4AI OFFLINE VIEW ---
class A4AIOfflineView extends StatelessWidget {
  final VoidCallback onRetry;

  const A4AIOfflineView({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/logo.png',
            height: 84,
            errorBuilder: (context, error, stackTrace) => Container(
              height: 80,
              width: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D0E),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.bolt_rounded,
                color: Colors.white,
                size: 44,
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            "No Internet Connection",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "Please check your Wi-Fi or mobile data network to continue using a4ai.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7280),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 36),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D0D0E),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0x26FFFFFF)),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.refresh_rounded, size: 19),
                  SizedBox(width: 8),
                  Text(
                    "Try Again",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}