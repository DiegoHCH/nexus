import 'package:nexus/core/usecase/usecase.dart';
import 'package:nexus/features/onboarding/domain/repositories/microphone_access.dart';

class RequestMicrophonePermission extends UseCase<bool, NoParams> {
  const RequestMicrophonePermission(this._microphone);

  final MicrophoneAccess _microphone;

  @override
  Future<bool> call(NoParams params) => _microphone.hasPermission();
}
