import 'package:nexus/core/usecase/usecase.dart';
import 'package:nexus/features/onboarding/domain/entities/onboarding_status.dart';
import 'package:nexus/features/onboarding/domain/repositories/gemini_key_store.dart';

class CheckOnboardingStatus extends UseCase<OnboardingStatus, NoParams> {
  const CheckOnboardingStatus(this._keyStore);

  final GeminiKeyStore _keyStore;

  @override
  Future<OnboardingStatus> call(NoParams params) async {
    final key = await _keyStore.read();
    return OnboardingStatus(hasGeminiKey: key != null && key.isNotEmpty);
  }
}
