import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
            // Check for connection/host errors
            if (error.errorCode == -2 || // ERR_INTERNET_DISCONNECTED
                error.errorCode == -6 || // ERR_CONNECTION_REFUSED
                error.errorCode == -8 || // ERR_CONNECTION_TIMED_OUT
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

            // Keep internal domain browsing inside the webview
            if (uri.host.contains('a4ai.in') || uri.host.contains('supabase.co')) {
              return NavigationDecision.navigate;
            }

            // Open external URLs (whatsapp, mailto, tel, docs) in external applications
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      );

    if (_controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      (_controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    _controller.loadRequest(Uri.parse(_initialUrl));
  }

  void _initNetworkMonitoring() {
    // Check initial connectivity asynchronously
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

    // Listen to real-time network state changes
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

        // Handle page-by-page web navigation
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
              // WebView component
              WebViewWidget(controller: _controller),

              // Top progress bar during page load
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

              // Branded Offline Screen
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
          // Logo placeholder / asset
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

          // Retry Button
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