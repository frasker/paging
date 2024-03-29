import 'package:paging/src/data_source.dart';

import 'positional_data_source.dart';

class WrapperPositionalDataSource<A, B> extends PositionalDataSource<B> {
  final PositionalDataSource<A> mSource;
  final List<B> Function(List<A> data) mListFunction;

  WrapperPositionalDataSource(this.mSource, this.mListFunction);

  @override
  void addInvalidatedCallback(onInvalidatedCallback) {
    mSource.addInvalidatedCallback(onInvalidatedCallback);
  }

  @override
  void removeInvalidatedCallback() {
    mSource.removeInvalidatedCallback();
  }

  @override
  Future<void> invalidate() {
    return mSource.invalidate();
  }

  @override
  bool get invalid => mSource.invalid;

  @override
  void loadInitial(PositionalLoadInitialParams params, PositionalLoadInitialCallback<B> callback) {
    mSource.loadInitial(params, _MyLoadInitialCallback<A, B>(callback,mListFunction));
  }

  @override
  void loadRange(LoadRangeParams params, LoadRangeCallback<B> callback) {
    mSource.loadRange(params, _MyLoadRangeCallback<A, B>(callback,mListFunction));
  }

  @override
  void onResultInitialFailed() {
    mSource.onResultInitialFailed();
  }
}

class _MyLoadInitialCallback<A, B> extends PositionalLoadInitialCallback<A> {
  final PositionalLoadInitialCallback<B> callback;
  final List<B> Function(List<A> data) mListFunction;

  _MyLoadInitialCallback(this.callback, this.mListFunction);

  @override
  void onResult(List<A> data, int position) {
    callback.onResult(DataSource.convert<A, B>(mListFunction, data), position);
  }

  @override
  void onResultInitial(List<A> data, int position, int totalCount) {
    callback.onResultInitial(
        DataSource.convert<A, B>(mListFunction, data), position, totalCount);
  }

  @override
  void onResultInitialFailed() {
    callback.onResultInitialFailed();
  }
}

class _MyLoadRangeCallback<A, B> extends LoadRangeCallback<A> {
  final LoadRangeCallback<B> callback;
  final List<B> Function(List<A> data) mListFunction;

  _MyLoadRangeCallback(this.callback, this.mListFunction);

  @override
  void onResult(List<A> data) {
    callback.onResult(DataSource.convert<A, B>(mListFunction, data));
  }
}
