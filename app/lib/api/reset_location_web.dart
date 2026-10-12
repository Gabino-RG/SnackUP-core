// ignore: deprecated_member_use
import 'dart:html' as html;

void clearResetLocation() =>
    html.window.history.replaceState(null, '', html.window.location.pathname);
