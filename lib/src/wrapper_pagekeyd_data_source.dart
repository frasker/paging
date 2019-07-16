import 'data_source.dart';
import 'pagekeyd_data_source.dart';

class WrapperPageKeyedDataSource<K, A, B> extends PageKeyedDataSource<K, B> {
  final PageKeyedDataSource<K, A> mSource;
  final List<B> Function(List<A> data) mListFunction;

  WrapperPageKeyedDataSource(this.mSource, this.mListFunction);

  @override
  void addInvalidatedCallback(onInvalidatedCallback) {
    mSource.addInvalidatedCallback(onInvalidatedCallback);
  }

  @override
  void removeInvalidatedCallback(onInvalidatedCallback) {
    mSource.removeInvalidatedCallback(onInvalidatedCallback);
  }

  @override
  void invalidate() {
    mSource.invalidate();
  }

  @override
  bool get invalid => mSource.invalid;

  @override
  void loadAfter(LoadParams<K> params, LoadCallback<K, B> callback) {
    return mSource.loadBefore(
        params, _MyAfterLoadCallback<K, A, B>(callback, mListFunction));
  }

  @override
  loadBefore(LoadParams<K> params, LoadCallback<K, B> callback) {
    return mSource.loadBefore(
        params, _MyBeforeLoadCallback<K, A, B>(callback, mListFunction));
  }

  @override
  void loadInitial(
      LoadInitialParams<K> params, LoadInitialCallback<K, B> callback) {
    mSource.loadInitial(
        params, _MyLoadInitialCallback<K, A, B>(callback, mListFunction));
  }
}

class _MyLoadInitialCallback<K, A, B> extends LoadInitialCallback<K, A> {
  final LoadInitialCallback<K, B> callback;
  final List<B> Function(List<A> data) mListFunction;

  _MyLoadInitialCallback(this.callback, this.mListFunction);

  @override
  void onResult(List<A> data, K previousPageKey, K nextPageKey) {
    callback.onResult(DataSource.convert<A, B>(mListFunction, data),
        previousPageKey, nextPageKey);
  }

  @override
  void onResultInitial(List<A> data, int position, int totalCount,
      K previousPageKey, K nextPageKey) {
    callback.onResultInitial(DataSource.convert<A, B>(mListFunction, data),
        position, totalCount, previousPageKey, nextPageKey);
  }
}

class _MyBeforeLoadCallback<K, A, B> extends LoadCallback<K, A> {
  final LoadCallback<K, B> callback;
  final List<B> Function(List<A> data) mListFunction;

  _MyBeforeLoadCallback(this.callback, this.mListFunction);

  @override
  void onResult(List<A> data, K adjacentPageKey) {
    callback.onResult(
        DataSource.convert<A, B>(mListFunction, data), adjacentPageKey);
  }
}

class _MyAfterLoadCallback<K, A, B> extends LoadCallback<K, A> {
  final LoadCallback<K, B> callback;
  final List<B> Function(List<A> data) mListFunction;

  _MyAfterLoadCallback(this.callback, this.mListFunction);

  @override
  void onResult(List<A> data, K adjacentPageKey) {
    callback.onResult(
        DataSource.convert<A, B>(mListFunction, data), adjacentPageKey);
  }
}
