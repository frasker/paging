import 'data_source.dart';
import 'itemkeyed_data_source.dart';

class WrapperItemKeyedDataSource<K, A, B> extends ItemKeyedDataSource<K, B> {
  final ItemKeyedDataSource<K, A> mSource;
  final List<B> Function(List<A> data) mListFunction;
  final Map<B, K> mKeyMap = Map();

  WrapperItemKeyedDataSource(this.mSource, this.mListFunction);

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

  List<B> convertWithStashedKeys(List<A> source) {
    List<B> dest = DataSource.convert<A, B>(mListFunction, source);
    for (int i = 0; i < dest.length; i++) {
      mKeyMap.putIfAbsent(dest[i], () {
        return mSource.getKeyByItem(source[i]);
      });
    }
    return dest;
  }

  @override
  K getKeyByItem(B item) {
    return mKeyMap[item];
  }

  @override
  void loadAfter(LoadParams<K> params, LoadCallback<B> callback) {
    mSource.loadAfter(params, _MyAfterLoadCallback<K, A, B>(callback, this));
  }

  @override
  void loadBefore(LoadParams<K> params, LoadCallback<B> callback) {
    mSource.loadBefore(params, _MyBeforeLoadCallback<K, A, B>(callback, this));
  }

  @override
  void loadInitial(
      LoadInitialParams<K> params, LoadInitialCallback<B> callback) {
    mSource.loadInitial(
        params, _MyLoadInitialCallback<K, A, B>(callback, this));
  }
}

class _MyLoadInitialCallback<K, A, B> extends LoadInitialCallback<A> {
  final LoadInitialCallback<B> callback;
  final WrapperItemKeyedDataSource<K, A, B> mDataSource;

  _MyLoadInitialCallback(this.callback, this.mDataSource);

  @override
  void onResult(List<A> data) {
    callback.onResult(mDataSource.convertWithStashedKeys(data));
  }

  @override
  void onResultInitial(List<A> data, int position, int totalCount) {
    callback.onResultInitial(
        mDataSource.convertWithStashedKeys(data), position, totalCount);
  }
}

class _MyBeforeLoadCallback<K, A, B> extends LoadCallback<A> {
  final LoadCallback<B> callback;
  final WrapperItemKeyedDataSource<K, A, B> mDataSource;

  _MyBeforeLoadCallback(this.callback, this.mDataSource);

  @override
  void onResult(List<A> data) {
    callback.onResult(mDataSource.convertWithStashedKeys(data));
  }
}

class _MyAfterLoadCallback<K, A, B> extends LoadCallback<A> {
  final LoadCallback<B> callback;
  final WrapperItemKeyedDataSource<K, A, B> mDataSource;

  _MyAfterLoadCallback(this.callback, this.mDataSource);

  @override
  void onResult(List<A> data) {
    callback.onResult(mDataSource.convertWithStashedKeys(data));
  }
}
