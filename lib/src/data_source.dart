import 'page_result.dart';

/// Called when the data backing the list has become invalid. This callback is typically used
/// to signal that a new data source is needed.
/// <p>
/// This callback will be invoked on the thread that calls {@link #invalidate()}. It is valid
/// for the data source to invalidate itself during its load methods, or for an outside
/// source to invalidate it.
typedef InvalidatedCallback = Function();

abstract class DataSource<Key, Value> {
  bool _mInvalid = false;
  Set<InvalidatedCallback> _mOnInvalidatedCallbacks = Set();

  bool isContiguous();

  void addInvalidatedCallback(InvalidatedCallback onInvalidatedCallback) {
    _mOnInvalidatedCallbacks.add(onInvalidatedCallback);
  }

  void removeInvalidatedCallback(InvalidatedCallback onInvalidatedCallback) {
    _mOnInvalidatedCallbacks.remove(onInvalidatedCallback);
  }

  void invalidate() {
    _mInvalid = true;
    _mOnInvalidatedCallbacks
        .forEach((InvalidatedCallback listener) => listener());
  }

  bool get invalid => _mInvalid;
}

abstract class Factory<Key, Value> {
  DataSource<Key, Value> create();
}

class LoadCallbackHelper<T> {
  static void validateInitialLoadParams(
      List<dynamic> data, int position, int totalCount) {
    if (position < 0) {
      throw new Exception("Position must be non-negative");
    }
    if (data.length + position > totalCount) {
      throw new Exception(
          "List size + position too large, last item in list beyond totalCount.");
    }
    if (data.length == 0 && totalCount > 0) {
      throw new Exception(
          "Initial result cannot be empty if items are present in data set.");
    }
  }

  final int mResultType;
  final DataSource _mDataSource;
  final PageResultReceiver<T> _mReceiver;

  bool mHasSignalled = false;

  LoadCallbackHelper(this._mDataSource, this.mResultType, this._mReceiver);

  /// Call before verifying args, or dispatching actul results
  ///
  /// @return true if DataSource was invalid, and invalid result dispatched
  bool dispatchInvalidResultIfInvalid() {
    if (_mDataSource.invalid) {
      dispatchResultToReceiver(PageResult.getInvalidResult<T>());
      return true;
    }
    return false;
  }

  void dispatchResultToReceiver(final PageResult<T> result) {
    if (mHasSignalled) {
      throw new Exception(
          "callback.onResult already called, cannot call again.");
    }
    mHasSignalled = true;
    _mReceiver.onPageResult(mResultType, result);
  }
}

