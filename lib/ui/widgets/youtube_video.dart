import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Video id from a YouTube link: youtu.be/ID, youtube.com/watch?v=ID,
/// /shorts/ID, /embed/ID, /live/ID. Null if it isn't a YouTube link.
String? youTubeId(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || u.host.isEmpty) return null;
  final host = u.host.replaceFirst('www.', '').replaceFirst('m.', '');
  final id = switch (host) {
    'youtu.be' => u.pathSegments.firstOrNull,
    'youtube.com' || 'youtube-nocookie.com' || 'music.youtube.com' =>
      u.queryParameters['v'] ??
          (u.pathSegments.length >= 2 && const {'shorts', 'embed', 'live', 'v'}.contains(u.pathSegments.first)
              ? u.pathSegments[1]
              : null),
    _ => null,
  };
  return id != null && RegExp(r'^[A-Za-z0-9_-]{6,}$').hasMatch(id) ? id : null;
}

/// Plays a YouTube video inside the app (YouTube's embedded player in a
/// web view), 16:9.
class YouTubeVideo extends StatefulWidget {
  const YouTubeVideo({super.key, required this.videoId});
  final String videoId;

  @override
  State<YouTubeVideo> createState() => _YouTubeVideoState();
}

class _YouTubeVideoState extends State<YouTubeVideo> {
  late final WebViewController _web = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Colors.black);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(YouTubeVideo old) {
    super.didUpdateWidget(old);
    if (old.videoId != widget.videoId) _load();
  }

  void _load() {
    // An iframe page with a real base URL: YouTube's embed needs a referrer
    // or it refuses to play ("Error 153").
    _web.loadHtmlString('''
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;height:100%;background:#000}iframe{border:0;width:100%;height:100%}</style></head>
<body><iframe src="https://www.youtube-nocookie.com/embed/${widget.videoId}?playsinline=1&rel=0&modestbranding=1"
allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture; fullscreen" allowfullscreen></iframe>
</body></html>''', baseUrl: 'https://localhost');
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: AspectRatio(
      aspectRatio: 16 / 9,
      child: WebViewWidget(controller: _web),
    ),
  );
}
