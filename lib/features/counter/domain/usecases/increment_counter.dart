import 'package:nexus/core/usecase/usecase.dart';
import 'package:nexus/features/counter/domain/entities/counter.dart';
import 'package:nexus/features/counter/domain/repositories/counter_repository.dart';

class IncrementCounter implements UseCase<Counter, NoParams> {
  const IncrementCounter(this._repository);

  final CounterRepository _repository;

  @override
  Future<Counter> call(NoParams params) => _repository.increment();
}
