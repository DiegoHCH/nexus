import 'package:nexus/features/remote/domain/remote_surface.dart';
import 'package:nexus/features/remote/domain/write_phrase.dart';
import 'package:nexus_protocol/nexus_protocol.dart';

/// Atiende lo que pide el teléfono.
///
/// No sabe nada de sockets: recibe un [Call] y devuelve los marcos que hay que
/// mandar, en orden. Así se prueba el despacho entero —incluido el reenvío, que es
/// la parte peligrosa— sin levantar un servidor ni fingir un WebSocket.
///
/// Y no sabe nada de la app: habla con [RemoteSurface], que es la costura de la
/// pieza anterior.
class Dispatcher {
  Dispatcher({
    required this.surface,
    required this.unlock,
    required this.phrases,
    Deduplicator? dedupe,
  }) : dedupe = dedupe ?? Deduplicator(ttl: const Duration(minutes: 10));

  final RemoteSurface surface;

  /// Quien concede y caduca el permiso de escritura.
  final WriteUnlock unlock;

  /// De donde sale la frase guardada. Se lee en cada intento y no se cachea: si se
  /// cacheara, cambiarla en Ajustes no cerraría la puerta hasta reiniciar.
  final WritePhraseStore phrases;

  final Deduplicator dedupe;

  /// El tope de cuántos mensajes puede pedir de una vez.
  ///
  /// Existe porque el límite lo manda el cliente y un cliente puede pedir cien mil.
  /// La paginación protege al teléfono de tragarse una sesión; esto protege al Mac
  /// de que se la pidan.
  static const maxPagina = 200;

  /// Los marcos a enviar, en orden.
  Stream<Frame> attend(Call call) async* {
    // **El ack antes de ejecutar, y esto es el orden y no un detalle.**
    //
    // Un encargo tarda minutos. Si la confirmación fuera con el resultado, el móvil
    // pasaría esos minutos sin saber si su petición llegó — y un móvil que no lo
    // sabe reenvía. De ahí sale el encargo que corre dos veces.
    final primeraVez = dedupe.aceptar(call.id);
    yield Ack(id: call.id, duplicate: !primeraVez);

    // Un reenvío se confirma y **no se ejecuta**. Es la razón de ser de todo esto:
    // con `acceptEdits` de por medio, ejecutarlo dos veces escribe dos veces.
    if (!primeraVez) return;

    final metodo = call.known;
    if (metodo == null) {
      // Un método que este Mac no conoce viene de un cliente más nuevo. Se contesta
      // con un error y no se cierra la conexión: el resto de lo que sabe pedir
      // sigue funcionando.
      yield Failure(
        id: call.id,
        code: 'unknownMethod',
        message: 'este Mac no conoce «${call.method}»',
      );
      return;
    }

    try {
      yield await _atender(metodo, call);
    } on UnknownConversation catch (error) {
      // No es un fallo del canal: el teléfono guarda ids y una conversación se
      // puede cerrar en el Mac mientras el móvil la tenía en pantalla.
      yield Failure(
        id: call.id,
        code: 'unknownConversation',
        message: 'la conversación ${error.id} ya no está abierta',
      );
    } on BinaryArtifact catch (error) {
      yield Failure(
        id: call.id,
        code: 'binaryArtifact',
        message: 'ese documento no es texto: ${error.id} se abre en el Mac',
      );
    } on FormatException catch (error) {
      yield Failure(id: call.id, code: 'badParams', message: error.message);
    } on Object catch (error) {
      // Lo que no se esperaba **se contesta igual**: dejar una petición sin
      // respuesta deja al teléfono esperando para siempre, que se ve como «no
      // responde» y manda a buscar el problema al sitio equivocado.
      //
      // El texto va sin detalles: lo que sabe el Mac se queda en su registro.
      yield Failure(
        id: call.id,
        code: 'internal',
        message: 'no se pudo atender',
      );
      // Y se relanza para que quede en el registro de quien lo llamó.
      throw StateError('$error');
    }
  }

  Future<Frame> _atender(RemoteMethod metodo, Call call) async {
    switch (metodo) {
      case RemoteMethod.conversations:
        final lista = await surface.conversations();
        return Result(
          id: call.id,
          data: {
            'conversations': [for (final c in lista) c.toJson()],
          },
        );

      case RemoteMethod.history:
        final pagina = await surface.history(
          _id(call),
          cursor: _entero(call, 'cursor', 0),
          limit: _entero(call, 'limit', 50).clamp(1, maxPagina),
        );
        return Result(
          id: call.id,
          data: {
            'messages': [for (final m in pagina.items) m.toJson()],
            'nextCursor': ?pagina.nextCursor,
          },
        );

      case RemoteMethod.meter:
        return Result(
          id: call.id,
          data: (await surface.meter(_id(call))).toJson(),
        );

      case RemoteMethod.permission:
        return Result(
          id: call.id,
          data: (await surface.permission(_id(call))).toJson(),
        );

      case RemoteMethod.sendErrand:
        final texto = (call.params['text'] as String?)?.trim() ?? '';
        if (texto.isEmpty) {
          throw const FormatException('el encargo llega vacío');
        }
        await surface.sendErrand(
          _id(call),
          texto,
          // **Solo la mitad remota del permiso.** La de la carpeta se aplica más
          // abajo, donde se decide el `canEdit`; hacerla también aquí sería tener
          // el mismo AND en dos sitios, y dos sitios se separan.
          allowWrites: unlock.puedeEscribir,
        );
        // El resultado dice **que arrancó**, no que terminara: un encargo dura
        // minutos y lo que pasa dentro llega como eventos.
        return Result(id: call.id, data: {'started': true});

      case RemoteMethod.stopErrand:
        await surface.stopErrand(_id(call));
        return Result(id: call.id, data: {'stopped': true});

      case RemoteMethod.archive:
        final pagina = await surface.archive(
          cursor: _entero(call, 'cursor', 0),
          limit: _entero(call, 'limit', 30).clamp(1, maxPagina),
        );
        return Result(
          id: call.id,
          data: {
            'conversations': [for (final c in pagina.items) c.toJson()],
            'nextCursor': ?pagina.nextCursor,
          },
        );

      case RemoteMethod.resumeConversation:
        final vivo = await surface.resumeConversation(_texto(call, 'archived'));
        // Se devuelve el id de la conversación **viva**, que puede no ser el del
        // archivo: si ya estaba abierta, lo correcto es llevar a esa en vez de abrir
        // una segunda sobre la misma carpeta.
        return Result(id: call.id, data: {'conversation': vivo});

      case RemoteMethod.folders:
        final carpetas = await surface.folders();
        return Result(
          id: call.id,
          data: {
            'folders': [for (final f in carpetas) f.toJson()],
          },
        );

      case RemoteMethod.openConversation:
        final id = await surface.openConversation(_texto(call, 'folder'));
        return Result(id: call.id, data: {'conversation': id});

      case RemoteMethod.artifacts:
        final lista = await surface.artifacts();
        return Result(
          id: call.id,
          data: {
            'artifacts': [for (final a in lista) a.toJson()],
          },
        );

      case RemoteMethod.artifact:
        return Result(
          id: call.id,
          data: {'content': await surface.artifact(_texto(call, 'artifact'))},
        );

      case RemoteMethod.unlockWrites:
        return _abrirEscritura(call);
    }
  }

  /// Abrir la escritura con la frase.
  ///
  /// Lo atiende el canal y no la app: la frase es un secreto del canal, y la app no
  /// tiene por qué verla pasar.
  Future<Frame> _abrirEscritura(Call call) async {
    final recibida = call.params['phrase'] as String?;
    if (recibida == null || recibida.isEmpty) {
      throw const FormatException('falta la frase');
    }

    final negado = unlock.intentar(
      guardada: await phrases.read(),
      recibida: recibida,
    );

    if (negado != null) {
      return Failure(
        id: call.id,
        code: switch (negado) {
          WriteDenial.sinFrase => 'noPhrase',
          WriteDenial.frase => 'wrongPhrase',
          WriteDenial.demasiadosIntentos => 'tooManyAttempts',
        },
        // **Sin decir cuál falló más allá del código, y sin repetir la frase.**
        // El código lo necesita el teléfono para saber qué enseñar; el valor no lo
        // necesita nadie, y este marco podría acabar en un registro.
        message: switch (negado) {
          WriteDenial.sinFrase =>
            'no hay frase de escritura definida en el Mac',
          WriteDenial.frase => 'la frase no es',
          WriteDenial.demasiadosIntentos => 'demasiados intentos',
        },
      );
    }

    return Result(
      id: call.id,
      data: {'until': unlock.grant!.until.toIso8601String()},
    );
  }

  /// Un parámetro de texto obligatorio.
  ///
  /// Uno solo para todos en vez de una comprobación por método: la que se escribe a
  /// mano en cada sitio es la que un día se olvida, y olvidarla aquí significa pasarle
  /// un `null` a la app.
  String _texto(Call call, String clave) {
    final valor = call.params[clave] as String?;
    if (valor == null || valor.isEmpty) {
      throw FormatException('falta «$clave»');
    }
    return valor;
  }

  String _id(Call call) {
    final id = call.params['conversation'] as String?;
    if (id == null || id.isEmpty) {
      throw const FormatException('falta «conversation»');
    }
    return id;
  }

  int _entero(Call call, String clave, int porDefecto) {
    final crudo = call.params[clave];
    if (crudo == null) return porDefecto;
    if (crudo is int) return crudo;
    // Un número que llega como texto es un cliente mal escrito, no un ataque: se
    // acepta si se entiende. Lo que no se hace es adivinar y seguir con basura.
    final leido = int.tryParse('$crudo');
    if (leido == null) throw FormatException('«$clave» no es un número');
    return leido;
  }
}
