import AppKit
import FlutterMacOS
import Foundation
import os

/// Nexus en la barra de estado del Mac: que se sepa que está y en qué anda.
///
/// Existe porque **la app ya se usa sin mirarla**: ⌥Espacio la despierta sin
/// traer la ventana al frente, y el trabajo de Claude dura minutos. Hasta ahora
/// no había forma de saber si seguía trabajando sin ir a buscar la ventana.
///
/// El dibujo no es el icono de la app: ese lleva su placa oscura, y en una barra
/// clara sería un cuadrado negro. Aquí se pinta solo la marca —el aro y el
/// horizonte, el mismo registro mínimo que usa el icono de 16 px— sobre nada.
final class NexusStatusItem: NSObject {
  private static let log = Logger(subsystem: "com.katanalabs.nexus", category: "barra")

  /// Se guarda con referencia fuerte: sin esto el sistema lo suelta y el icono
  /// desaparece de la barra a los pocos segundos.
  private static var item: NSStatusItem?

  /// Lo que enseña el icono.
  ///
  /// Son **tres y no cuatro**, y es una decisión y no un descuido: a 16 px no
  /// caben cuatro estados legibles. «Hablando» y «escuchando» comparten aspecto
  /// —los dos son «está contigo»— y lo que sí se distingue es lo que la ficha
  /// pedía: si el trabajo sigue en marcha.
  enum Presence: String {
    case asleep, active, working

    static func from(_ raw: String) -> Presence {
      switch raw {
      case "listen", "speak": return .active
      case "think": return .working
      default: return .asleep
      }
    }
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.katanalabs.nexus/status",
      binaryMessenger: registrar.messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "setState":
        let raw = (call.arguments as? [String: Any])?["state"] as? String ?? ""
        show(Presence.from(raw))
        result(nil)
      // Los rótulos vienen de Dart y no se escriben aquí: el idioma lo elige la
      // app —puede no ser el del sistema— y su diccionario ya lo sabe.
      case "setMenu":
        buildMenu((call.arguments as? [String: Any]) ?? [:], channel: channel)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    show(.asleep)
    log.info("canal de barra de estado registrado")
  }

  /// El icono que hay puesto ahora mismo, para poder mirarlo desde una prueba:
  /// que los tres estados existan no sirve de nada si pintan lo mismo.
  static var currentImage: NSImage? { item?.button?.image }

  static var currentButton: NSStatusBarButton? { item?.button }

  static var currentMenu: NSMenu? { item?.menu }

  /// Para probar el menú sin un canal al otro lado: lo que se comprueba es que
  /// las filas se construyan con lo que llega, no qué hace cada una.
  static func setMenuForTesting(_ labels: [String: Any]) {
    show(.asleep)
    buildMenu(labels, channel: nil)
  }

  /// El menú que se abre al pulsarlo.
  ///
  /// Sin menú, pulsar el icono **resaltaba el botón y no hacía nada**: quedaba
  /// un recuadro oscuro encendido sin explicación, que es lo que se reportó. Un
  /// icono en la barra que no se puede pulsar no es presencia, es un adorno que
  /// parece roto.
  private static func buildMenu(_ labels: [String: Any], channel: FlutterMethodChannel?) {
    let menu = NSMenu()

    func add(_ key: String, _ action: @escaping () -> Void, _ tecla: String = "") {
      guard let title = labels[key] as? String, !title.isEmpty else { return }
      let item = NSMenuItem(title: title, action: #selector(Trampolin.disparar), keyEquivalent: tecla)
      item.target = Trampolin.shared
      item.representedObject = action
      menu.addItem(item)
    }

    // El aviso de versión nueva va **primero y solo cuando lo hay**: es lo único
    // del menú que caduca, y enterrarlo debajo de «hablar» sería esconder la
    // única fila que trae información nueva.
    //
    // Abre el enlace aquí y no en Dart porque no hay nada que decidir: es una URL
    // que ya viene resuelta, y darle la vuelta por el canal solo añade un salto.
    if let aviso = labels["update"] as? String, !aviso.isEmpty,
       let enlace = (labels["updateUrl"] as? String).flatMap(URL.init(string:)) {
      let item = NSMenuItem(
        title: aviso, action: #selector(Trampolin.disparar), keyEquivalent: ""
      )
      item.target = Trampolin.shared
      item.representedObject = { NSWorkspace.shared.open(enlace) } as () -> Void
      menu.addItem(item)
      menu.addItem(.separator())
    }

    // Hablar y ajustes los resuelve Dart: son estado de la app, no del sistema.
    add("talk", { channel?.invokeMethod("talk", arguments: nil) })
    add("show", {
      NSApp.activate(ignoringOtherApps: true)
      NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    })
    menu.addItem(.separator())
    add("settings", { channel?.invokeMethod("settings", arguments: nil) }, ",")
    menu.addItem(.separator())
    add("quit", { NSApp.terminate(nil) }, "q")

    item?.menu = menu
  }

  static func show(_ presence: Presence) {
    let bar = item ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item = bar
    bar.button?.image = mark(for: presence)
    bar.button?.toolTip = "Nexus"
  }

  /// La marca, dibujada a cualquier escala.
  ///
  /// `NSImage(size:flipped:drawingHandler:)` y no un PNG: el bloque se vuelve a
  /// ejecutar en cada pantalla, así que sale nítido en Retina sin llevar dos
  /// mapas de bits.
  private static func mark(for presence: Presence) -> NSImage {
    let lado: CGFloat = 16
    let imagen = NSImage(size: NSSize(width: lado, height: lado), flipped: false) { rect in
      let color: NSColor = presence == .asleep
        ? .black  // lo tiñe el sistema: ver `isTemplate` abajo
        : NSColor(red: 0x56 / 255, green: 0xE1 / 255, blue: 0xEA / 255, alpha: 1)
      color.setStroke()
      color.setFill()

      // El aro, con margen para que no toque los bordes de la ranura.
      let r: CGFloat = 5
      let centro = NSPoint(x: rect.midX, y: rect.midY)
      let aro = NSBezierPath(ovalIn: NSRect(
        x: centro.x - r, y: centro.y - r, width: r * 2, height: r * 2
      ))
      aro.lineWidth = 1.5
      aro.stroke()

      // El horizonte, que es lo que hace que la mancha se lea como un objeto
      // mirado y no como una «o».
      let horizonte = NSBezierPath()
      horizonte.move(to: NSPoint(x: centro.x - r - 1.5, y: centro.y))
      horizonte.line(to: NSPoint(x: centro.x + r + 1.5, y: centro.y))
      horizonte.lineWidth = 1
      horizonte.stroke()

      // Trabajando: un punto en el centro. Es la única diferencia que se
      // distingue de verdad a este tamaño, y es la que importa — saber si
      // Claude sigue en marcha sin ir a buscar la ventana.
      if presence == .working {
        NSBezierPath(ovalIn: NSRect(
          x: centro.x - 1.5, y: centro.y - 1.5, width: 3, height: 3
        )).fill()
      }
      return true
    }

    // Dormido va como plantilla: el sistema lo tiñe según la barra, así que se
    // ve bien en claro y en oscuro. En activo **no**, porque ahí el color es la
    // información: si lo tiñera, «escuchando» y «dormido» serían idénticos.
    imagen.isTemplate = presence == .asleep
    return imagen
  }
}

/// Un objetivo para los `NSMenuItem`, que exigen un selector de Objective-C.
///
/// Existe solo para poder escribir cada acción como una clausura al lado de su
/// rótulo, en vez de repartirlas en métodos sueltos que hay que ir a buscar.
final class Trampolin: NSObject {
  static let shared = Trampolin()

  @objc func disparar(_ sender: NSMenuItem) {
    (sender.representedObject as? () -> Void)?()
  }
}
