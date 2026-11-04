{{flutter_js}}
{{flutter_build_config}}

// The local server supplies the current release. Avoid a stale service worker
// serving a different API contract when a PC review package is upgraded.
_flutter.loader.load({config: {canvasKitBaseUrl: 'canvaskit/'}});
