import 'package:flutter/services.dart';

/// Las órdenes que entran desde el menú nativo de macOS.
///
/// Existe porque AppKit resuelve los equivalentes de teclado del menú antes de
/// entregarle la tecla a Flutter: ⌘, se lo queda el elemento «Ajustes…» y nunca
/// llega a un atajo escrito en Dart. Así que el camino va al revés —el menú
/// avisa, la app abre— y funciona tenga el foco quien lo tenga.
class AppMenuChannel {
  const AppMenuChannel._();

  static const _channel = MethodChannel('com.katanalabs.nexus/menu');

  static void listen({
    required void Function() onOpenSettings,
    required void Function() onOpenHistory,
    required void Function() onOpenArtifacts,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'openSettings':
          onOpenSettings();
        case 'openHistory':
          onOpenHistory();
        case 'openArtifacts':
          onOpenArtifacts();
      }
    });
  }
}
