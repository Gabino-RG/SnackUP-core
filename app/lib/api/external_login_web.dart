// ignore: deprecated_member_use
import 'dart:html' as html;

void beginExternalLogin(Uri uri) => html.window.location.assign(uri.toString());
