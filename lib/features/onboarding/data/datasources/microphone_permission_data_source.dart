import 'package:record/record.dart';

/// Envuelve solo `hasPermission()` del paquete de grabación. Pedirlo puede
/// abrir el diálogo del sistema la primera vez; macOS lo va a negar si el
/// usuario dice que no.
class MicrophonePermissionDataSource {
  MicrophonePermissionDataSource({AudioRecorder? recorder}) : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  Future<bool> hasPermission() => _recorder.hasPermission();
}
