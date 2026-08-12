import 'package:nexus/features/onboarding/data/datasources/microphone_permission_data_source.dart';
import 'package:nexus/features/onboarding/domain/repositories/microphone_access.dart';

class MicrophoneAccessImpl implements MicrophoneAccess {
  const MicrophoneAccessImpl(this._dataSource);

  final MicrophonePermissionDataSource _dataSource;

  @override
  Future<bool> hasPermission() => _dataSource.hasPermission();
}
