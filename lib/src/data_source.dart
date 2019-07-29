import 'dart:async';

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
  Set<InvalidatedCallback> _mToRemoveCallbacks = Set();

  bool isContiguous();

  void addInvalidatedCallback(InvalidatedCallback onInvalidatedCallback) {
    _mOnInvalidatedCallbacks.add(onInvalidatedCallback);
  }

  void removeInvalidatedCallback(InvalidatedCallback onInvalidatedCallback) {
    _mToRemoveCallbacks.add(onInvalidatedCallback);
  }

  Future<void> invalidate() async {
    _mInvalid = true;
    var completer = Completer<void>.sync();
    Future((){
      _mOnInvalidatedCallbacks
          .forEach((InvalidatedCallback listener) => listener());
      _mOnInvalidatedCallbacks
          .removeWhere((e) => _mToRemoveCallbacks.contains(e));
      _mToRemoveCallbacks.clear();
      completer.complete();
    });
    return completer.future;
  }

  bool get invalid => _mInvalid;

  DataSource<Key, ToValue> map<ToValue>(ToValue func(Value data));

  DataSource<Key, ToValue> mapByPage<ToValue>(
      List<ToValue> func(List<Value> data));

  static List<Y> Function(List<X> source) createListFunction<X, Y>(
      Y func(X x)) {
    return (List<X> source) {
      List<Y> out = List<Y>(source.length);
      for (int i = 0; i < out.length; i++) {
        out.add(func(source[i]));
      }
      return out;
    };
  }

  static List<B> convert<A, B>(List<B> func(List<A> source), List<A> source) {
    List<B> dest = func.call(source);
    if (dest.length != source.length) {
      throw new Exception(
          "Invalid Function changed return size. This is not supported.");
    }
    return dest;
  }
}

abstract class Factory<Key, Value> {
  DataSource<Key, Value> create();

  /// Applies the given function to each value emitted by DataSources produced by this Factory.
  /// <p>
  /// Same as {@link #mapByPage(Function)}, but operates on individual items.
  ///
  /// @param function Function that runs on each loaded item, returning items of a potentially
  ///                  new type.
  /// @param <ToValue> Type of items produced by the new DataSource, from the passed function.
  ///
  /// @return A new DataSource.Factory, which transforms items using the given function.
  ///
  /// @see #mapByPage(Function)
  /// @see DataSource#map(Function)
  /// @see DataSource#mapByPage(Function)
  Factory<Key, ToValue> map<ToValue>(ToValue func(Value data)) {
    return mapByPage<ToValue>(
        DataSource.createListFunction<Value, ToValue>(func));
  }

  /// Applies the given function to each value emitted by DataSources produced by this Factory.
  /// <p>
  /// Same as {@link #map(Function)}, but allows for batch conversions.
  ///
  /// @param function Function that runs on each loaded page, returning items of a potentially
  ///                  new type.
  /// @param <ToValue> Type of items produced by the new DataSource, from the passed function.
  ///
  /// @return A new DataSource.Factory, which transforms items using the given function.
  ///
  /// @see #map(Function)
  /// @see DataSource#map(Function)
  /// @see DataSource#mapByPage(Function)
  Factory<Key, ToValue> mapByPage<ToValue>(
      List<ToValue> func(List<Value> data)) {
    return _MapByPageFactory<Key, Value, ToValue>(func, this);
  }
}

class _MapByPageFactory<Key, Value, ToValue> extends Factory<Key, ToValue> {
  final List<ToValue> Function(List<Value> value) func;
  final Factory<Key, Value> factory;

  _MapByPageFactory(this.func, this.factory);

  @override
  DataSource<Key, ToValue> create() {
    return factory.create().mapByPage<ToValue>(func);
  }
}

class LoadCallbackHelper<Key, Value> {
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
  final DataSource<Key, Value> _mDataSource;
  final PageResultReceiver<Value> _mReceiver;

  bool mHasSignalled = false;

  LoadCallbackHelper(this._mDataSource, this.mResultType, this._mReceiver);

  /// Call before verifying args, or dispatching actul results
  ///
  /// @return true if DataSource was invalid, and invalid result dispatched
  bool dispatchInvalidResultIfInvalid() {
    if (_mDataSource.invalid) {
      dispatchResultToReceiver(PageResult.getInvalidResult<Value>());
      return true;
    }
    return false;
  }

  void dispatchResultToReceiver(final PageResult<Value> result) {
    if (mHasSignalled) {
      throw new Exception(
          "callback.onResult already called, cannot call again.");
    }
    mHasSignalled = true;
    _mReceiver.onPageResult(mResultType, result);
  }
}
