abstract class UseCase<ReturnType, Params> {
  const UseCase();

  Future<ReturnType> call(Params params);
}

class NoParams {
  const NoParams();
}
