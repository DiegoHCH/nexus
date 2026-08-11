import 'package:nexus/features/counter/data/datasources/counter_local_data_source.dart';
import 'package:nexus/features/counter/domain/entities/counter.dart';
import 'package:nexus/features/counter/domain/repositories/counter_repository.dart';

class CounterRepositoryImpl implements CounterRepository {
  const CounterRepositoryImpl(this._localDataSource);

  final CounterLocalDataSource _localDataSource;

  @override
  Future<Counter> getCounter() async =>
      Counter(await _localDataSource.getCounter());

  @override
  Future<Counter> increment() async =>
      Counter(await _localDataSource.increment());
}
