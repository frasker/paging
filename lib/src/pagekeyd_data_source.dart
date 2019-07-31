import 'dart:async';

import 'package:paging/src/data_source.dart';
import 'package:paging/src/data_source.dart';

import 'contiguous_data_source.dart';
import 'data_source.dart';
import 'page_result.dart';
import 'wrapper_pagekeyd_data_source.dart';

abstract class PageKeyedDataSource<Key, Value>
    extends ContiguousDataSource<Key, Value> {
  Key mNextKey;

  Key mPreviousKey;

  void initKeys(Key previousKey, Key nextKey) {
    mPreviousKey = previousKey;
    mNextKey = nextKey;
  }

  void setPreviousKey(Key previousKey) {
    mPreviousKey = previousKey;
  }

  void setNextKey(Key nextKey) {
    mNextKey = nextKey;
  }

  Key getPreviousKey() {
    return mPreviousKey;
  }

  Key getNextKey() {
    return mNextKey;
  }

  @override
  void dispatchLoadAfter(int currentEndIndex, Value currentEndItem,
      int pageSize, PageResultReceiver<Value> receiver) {
    Key key = getNextKey();
    if (key != null) {
      loadAfter(new LoadParams<Key>(key, pageSize),
          new LoadCallbackImpl<Key, Value>(this, PageResult.APPEND, receiver));
    } else {
      receiver.onPageResult(
          PageResult.APPEND, PageResult.getEmptyResult<Value>());
    }
  }

  @override
  void dispatchLoadBefore(int currentBeginIndex, Value currentBeginItem,
      int pageSize, PageResultReceiver<Value> receiver) {
    Key key = getPreviousKey();
    if (key != null) {
      loadBefore(LoadParams<Key>(key, pageSize),
          new LoadCallbackImpl<Key, Value>(this, PageResult.PREPEND, receiver));
    } else {
      receiver.onPageResult(
          PageResult.PREPEND, PageResult.getEmptyResult<Value>());
    }
  }

  @override
  void dispatchLoadInitial(
      Key key,
      int initialLoadSize,
      int pageSize,
      bool enablePlaceholders,
      PageResultReceiver<Value> receiver,
      Completer<void> completer) {
    LoadInitialCallbackImpl<Key, Value> callback =
        LoadInitialCallbackImpl<Key, Value>(
            this, enablePlaceholders, receiver, completer);
    loadInitial(
        LoadInitialParams<Key>(initialLoadSize, enablePlaceholders), callback);
  }

  void loadInitial(
      LoadInitialParams<Key> params, LoadInitialCallback<Key, Value> callback);

  void loadAfter(LoadParams<Key> params, LoadCallback<Key, Value> callback);

  loadBefore(LoadParams<Key> params, LoadCallback<Key, Value> callback);

  @override
  Key getKey(int position, Value item) {
    // don't attempt to persist keys, since we currently don't pass them to initial load
    return null;
  }

  @override
  bool supportsPageDropping() {
    /* To support page dropping when PageKeyed, we'll need to:
     *    - Stash keys for every page we have loaded (can id by index relative to loadInitial)
     *    - Drop keys for any page not adjacent to loaded content
     *    - And either:
     *        - Allow impl to signal previous page key: onResult(data, nextPageKey, prevPageKey)
     *        - Re-trigger loadInitial, and break assumption it will only occur once.
     */
    return false;
  }

  @override
  PageKeyedDataSource<Key, ToValue> mapByPage<ToValue>(
      List<ToValue> Function(List<Value> data) func) {
    return WrapperPageKeyedDataSource<Key, Value, ToValue>(this, func);
  }

  @override
  PageKeyedDataSource<Key, ToValue> map<ToValue>(
      ToValue Function(Value data) func) {
    return mapByPage<ToValue>(
        DataSource.createListFunction<Value, ToValue>(func));
  }
}

class LoadInitialParams<Key> {
  /// Requested number of items to load.
  /// <p>
  /// Note that this may be larger than available data.
  final int requestedLoadSize;

  /// Defines whether placeholders are enabled, and whether the total count passed to
  /// {@link LoadInitialCallback#onResult(List, int, int, Key, Key)} will be ignored.
  final bool placeholdersEnabled;

  LoadInitialParams(this.requestedLoadSize, this.placeholdersEnabled);
}

class LoadParams<Key> {
  /// Load items before/after this key.
  /// <p>
  /// Returned data must begin directly adjacent to this position.
  final Key key;

  /// Requested number of items to load.
  /// <p>
  /// Returned page can be of this size, but it may be altered if that is easier, e.g. a
  /// network data source where the backend defines page size.
  final int requestedLoadSize;

  LoadParams(this.key, this.requestedLoadSize);
}

abstract class LoadInitialCallback<Key, Value> {
  /// Called to pass initial load state from a DataSource.
  /// <p>
  /// Call this method from your DataSource's {@code loadInitial} function to return data,
  /// and inform how many placeholders should be shown before and after. If counting is cheap
  /// to compute (for example, if a network load returns the information regardless), it's
  /// recommended to pass data back through this method.
  /// <p>
  /// It is always valid to pass a different amount of data than what is requested. Pass an
  /// empty list if there is no more data to load.
  ///
  /// @param data List of items loaded from the DataSource. If this is empty, the DataSource
  ///             is treated as empty, and no further loads will occur.
  /// @param position Position of the item at the front of the list. If there are {@code N}
  ///                 items before the items in data that can be loaded from this DataSource,
  ///                 pass {@code N}.
  /// @param totalCount Total number of items that may be returned from this DataSource.
  ///                   Includes the number in the initial {@code data} parameter
  ///                   as well as any items that can be loaded in front or behind of
  ///                   {@code data}.
  void onResultInitial(List<Value> data, int position, int totalCount,
      Key previousPageKey, Key nextPageKey);

  /// Called to pass loaded data from a DataSource.
  /// <p>
  /// Call this from {@link #loadInitial(LoadInitialParams, LoadInitialCallback)} to
  /// initialize without counting available data, or supporting placeholders.
  /// <p>
  /// It is always valid to pass a different amount of data than what is requested. Pass an
  /// empty list if there is no more data to load.
  ///
  /// @param data List of items loaded from the PageKeyedDataSource.
  /// @param previousPageKey Key for page before the initial load result, or {@code null} if no
  ///                        more data can be loaded before.
  /// @param nextPageKey Key for page after the initial load result, or {@code null} if no
  ///                        more data can be loaded after.
  void onResult(List<Value> data, Key previousPageKey, Key nextPageKey);
}

class LoadInitialCallbackImpl<Key, Value>
    extends LoadInitialCallback<Key, Value> {
  LoadCallbackHelper<Key, Value> mCallbackHelper;
  PageKeyedDataSource<Key, Value> _mDataSource;
  bool _mCountingEnabled;
  Completer<void> _mCompleter;

  LoadInitialCallbackImpl(
      PageKeyedDataSource<Key, Value> dataSource,
      bool countingEnabled,
      PageResultReceiver<Value> receiver,
      Completer<void> completer) {
    this.mCallbackHelper =
        LoadCallbackHelper<Key, Value>(dataSource, PageResult.INIT, receiver);
    this._mDataSource = dataSource;
    this._mCountingEnabled = countingEnabled;
    this._mCompleter = completer;
  }

  @override
  void onResult(List<Value> data, Key previousPageKey, Key nextPageKey) {
    if (!mCallbackHelper.dispatchInvalidResultIfInvalid()) {
      _mDataSource.initKeys(previousPageKey, nextPageKey);
      mCallbackHelper.dispatchResultToReceiver(PageResult<Value>(data, 0));
      _mCompleter.complete();
    } else {
      _mCompleter.completeError(null);
    }
  }

  @override
  void onResultInitial(List<Value> data, int position, int totalCount,
      Key previousPageKey, Key nextPageKey) {
    if (!mCallbackHelper.dispatchInvalidResultIfInvalid()) {
      LoadCallbackHelper.validateInitialLoadParams(data, position, totalCount);

      // setup keys before dispatching data, so guaranteed to be ready
      _mDataSource.initKeys(previousPageKey, nextPageKey);

      int trailingUnloadedCount = totalCount - position - data.length;
      if (_mCountingEnabled) {
        mCallbackHelper.dispatchResultToReceiver(PageResult<Value>(data, 0,
            leadingNulls: position, trailingNulls: trailingUnloadedCount));
      } else {
        mCallbackHelper
            .dispatchResultToReceiver(PageResult<Value>(data, position));
      }
    }
  }
}

abstract class LoadCallback<Key, Value> {
  /// Called to pass loaded data from a DataSource.
  /// <p>
  /// Call this method from your PageKeyedDataSource's
  /// {@link #loadBefore(LoadParams, LoadCallback)} and
  /// {@link #loadAfter(LoadParams, LoadCallback)} methods to return data.
  /// <p>
  /// It is always valid to pass a different amount of data than what is requested. Pass an
  /// empty list if there is no more data to load.
  /// <p>
  /// Pass the key for the subsequent page to load to adjacentPageKey. For example, if you've
  /// loaded a page in {@link #loadBefore(LoadParams, LoadCallback)}, pass the key for the
  /// previous page, or {@code null} if the loaded page is the first. If in
  /// {@link #loadAfter(LoadParams, LoadCallback)}, pass the key for the next page, or
  /// {@code null} if the loaded page is the last.
  ///
  /// @param data List of items loaded from the PageKeyedDataSource.
  /// @param adjacentPageKey Key for subsequent page load (previous page in {@link #loadBefore}
  ///                        / next page in {@link #loadAfter}), or {@code null} if there are
  ///                        no more pages to load in the current load direction.
  void onResult(List<Value> data, Key adjacentPageKey);
}

class LoadCallbackImpl<Key, Value> extends LoadCallback<Key, Value> {
  LoadCallbackHelper<Key, Value> _mCallbackHelper;
  PageKeyedDataSource<Key, Value> _mDataSource;

  LoadCallbackImpl(PageKeyedDataSource<Key, Value> dataSource, int type,
      PageResultReceiver<Value> receiver) {
    _mCallbackHelper =
        LoadCallbackHelper<Key, Value>(dataSource, type, receiver);
    _mDataSource = dataSource;
  }

  @override
  void onResult(List<Value> data, Key adjacentPageKey) {
    if (!_mCallbackHelper.dispatchInvalidResultIfInvalid()) {
      if (_mCallbackHelper.mResultType == PageResult.APPEND) {
        _mDataSource.setNextKey(adjacentPageKey);
      } else {
        _mDataSource.setPreviousKey(adjacentPageKey);
      }
      _mCallbackHelper.dispatchResultToReceiver(PageResult<Value>(data, 0));
    }
  }
}
