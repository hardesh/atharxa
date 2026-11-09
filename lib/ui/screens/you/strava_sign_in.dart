import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../services/strava.dart';

/// Strava's sign-in page inside the app. When Strava sends the browser to
/// [StravaClient.redirectUri], the page closes with the authorization code
/// (or null if the user declined or closed it).
class StravaSignInPage extends StatefulWidget {
  const StravaSignInPage({super.key, required this.clientId});
  final String clientId;

  static Future<String?> open(BuildContext context, String clientId) =>
      Navigator.push<String?>(context, MaterialPageRoute(builder: (_) => StravaSignInPage(clientId: clientId)));

  @override
  State<StravaSignInPage> createState() => _StravaSignInPageState();
}

class _StravaSignInPageState extends State<StravaSignInPage> {
  var _loading = true;

  late final WebViewController _web = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (r) {
          if (!r.url.startsWith(StravaClient.redirectUri)) return NavigationDecision.navigate;
          final q = Uri.parse(r.url).queryParameters;
          // Declined: "error=access_denied". The upload scope must be granted
          // for "Upload to Strava"; reading works without it.
          Navigator.pop(context, q['error'] == null ? q['code'] : null);
          return NavigationDecision.prevent;
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
      ),
    )
    ..loadRequest(StravaClient.authorizeUrl(widget.clientId));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Connect Strava'),
      bottom: _loading
          ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator())
          : null,
    ),
    body: WebViewWidget(controller: _web),
  );
}
