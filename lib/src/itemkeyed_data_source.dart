import 'contiguous_data_source.dart';
import 'data_source.dart';
import 'page_result.dart';
import 'wrapper_itemkeyed_data_source.dart';


/// Incremental data loader for paging keyed content, where loaded content uses previously loaded
/// items as input to future loads.
/// <p>
/// Implement a DataSource using ItemKeyedDataSource if you need to use data from item {@code N - 1}
/// to load item {@code N}. This is common, for example, in sorted database queries where
/// attributes of the item such just before the next query define how to execute it.
/// <p>
/// The {@code InMemoryByItemRepository} in the
/// <a href="https://github.com/googlesamples/android-architecture-components/blob/master/PagingWithNetworkSample/README.md">PagingWithNetworkSample</a>
/// shows how to implement a network ItemKeyedDataSource using
/// <a href="https://square.github.io/retrofit/">Retrofit</a>, while
/// handling swipe-to-refresh, network errors, and retry.
///
/// @param <Key> Type of data used to query Value types out of the DataSource.
/// @param <Value> Type of items being loaded by the DataSource.
abstract class ItemKeyedDataSource<Key, Value>
    extends ContiguousDataSource<Key, Value> {
  @override
  Key getKey(int position, Value item) {
    if (item == null) {
      return null;
    }

    return getKeyByItem(item);
  }

  /// Return a key associated with the given item.
  /// <p>
  /// If your ItemKeyedDataSource is loading from a source that is sorted and loaded by a unique
  /// integer ID, you would return {@code item.getID()} here. This key can then be passed to
  /// {@link #loadBefore(LoadParams, LoadCallback)} or
  /// {@link #loadAfter(LoadParams, LoadCallback)} to load additional items adjacent to the item
  /// passed to this function.
  /// <p>
  /// If your key is more complex, such as when you're sorting by name, then resolving collisions
  /// with integer ID, you'll need to return both. In such a case you would use a wrapper class,
  /// such as {@code Pair<String, Integer>} or, in Kotlin,
  /// {@code data class Key(val name: String, val id: Int)}
  ///
  /// @param item Item to get the key from.
  /// @return Key associated with given item.
  Key getKeyByItem(Value item);

  @override
  void dispatchLoadInitial(Key key, int initialLoadSize, int pageSize,
      bool enablePlaceholders, PageResultReceiver<Value> receiver) {
    LoadInitialCallbackImpl<Key, Value> callback =
        LoadInitialCallbackImpl<Key, Value>(this, enablePlaceholders, receiver);
    loadInitial(
        LoadInitialParams<Key>(key, initialLoadSize, enablePlaceholders),
        callback);
  }

  @override
  void dispatchLoadAfter(int currentEndIndex, Value currentEndItem,
      int pageSize, PageResultReceiver<Value> receiver) {
    loadAfter(new LoadParams<Key>(getKeyByItem(currentEndItem), pageSize),
        new LoadCallbackImpl<Key, Value>(this, PageResult.APPEND, receiver));
  }

  @override
  void dispatchLoadBefore(int currentBeginIndex, Value currentBeginItem,
      int pageSize, PageResultReceiver<Value> receiver) {
    loadBefore(LoadParams<Key>(getKeyByItem(currentBeginItem), pageSize),
        new LoadCallbackImpl<Key, Value>(this, PageResult.PREPEND, receiver));
  }

  /// Load initial data.
  /// <p>
  /// This method is called first to initialize a PagedList with data. If it's possible to count
  /// the items that can be loaded by the DataSource, it's recommended to pass the loaded data to
  /// the callback via the three-parameter
  /// {@link LoadInitialCallback#onResult(List, int, int)}. This enables PagedLists
  /// presenting data from this source to display placeholders to represent unloaded items.
  /// <p>
  /// {@link LoadInitialParams#requestedInitialKey} and {@link LoadInitialParams#requestedLoadSize}
  /// are hints, not requirements, so they may be altered or ignored. Note that ignoring the
  /// {@code requestedInitialKey} can prevent subsequent PagedList/DataSource pairs from
  /// initializing at the same location. If your data source never invalidates (for example,
  /// loading from the network without the network ever signalling that old data must be reloaded),
  /// it's fine to ignore the {@code initialLoadKey} and always start from the beginning of the
  /// data set.
  ///
  /// @param params Parameters for initial load, including initial key and requested size.
  /// @param callback Callback that receives initial load data.
  void loadInitial(
      LoadInitialParams<Key> params, LoadInitialCallback<Value> callback);

  /// Load list data before the key specified in {@link LoadParams#key LoadParams.key}.
  /// <p>
  /// It's valid to return a different list size than the page size if it's easier, e.g. if your
  /// backend defines page sizes. It is generally safer to increase the number loaded than reduce.
  /// <p>
  /// <p class="note"><strong>Note:</strong> Data returned will be prepended just before the key
  /// passed, so if you vary size, ensure that the last item is adjacent to the passed key.
  /// <p>
  /// Data may be passed synchronously during the loadBefore method, or deferred and called at a
  /// later time. Further loads going up will be blocked until the callback is called.
  /// <p>
  /// If data cannot be loaded (for example, if the request is invalid, or the data would be stale
  /// and inconsistent, it is valid to call {@link #invalidate()} to invalidate the data source,
  /// and prevent further loading.
  ///
  /// @param params Parameters for the load, including the key to load before, and requested size.
  /// @param callback Callback that receives loaded data.
  void loadBefore(LoadParams<Key> params, LoadCallback<Value> callback);

  /// Load list data after the key specified in {@link LoadParams#key LoadParams.key}.
  /// <p>
  /// It's valid to return a different list size than the page size if it's easier, e.g. if your
  /// backend defines page sizes. It is generally safer to increase the number loaded than reduce.
  /// <p>
  /// Data may be passed synchronously during the loadAfter method, or deferred and called at a
  /// later time. Further loads going down will be blocked until the callback is called.
  /// <p>
  /// If data cannot be loaded (for example, if the request is invalid, or the data would be stale
  /// and inconsistent, it is valid to call {@link #invalidate()} to invalidate the data source,
  /// and prevent further loading.
  ///
  /// @param params Parameters for the load, including the key to load after, and requested size.
  /// @param callback Callback that receives loaded data.
  void loadAfter(LoadParams<Key> params, LoadCallback<Value> callback);

  @override
  ItemKeyedDataSource<Key, ToValue> mapByPage<ToValue>(
      List<ToValue> Function(List<Value> data) func) {
    return WrapperItemKeyedDataSource<Key, Value, ToValue>(this, func);
  }

  @override
  ItemKeyedDataSource<Key, ToValue> map<ToValue>(
      ToValue Function(Value data) func) {
    return mapByPage<ToValue>(
        DataSource.createListFunction<Value, ToValue>(func));
  }
}

/// Holder object for inputs to {@link #loadInitial(LoadInitialParams, LoadInitialCallback)}.
///
/// @param <Key> Type of data used to query Value types out of the DataSource.
class LoadInitialParams<Key> {
  /// Load items around this key, or at the beginning of the data set if {@code null} is
  /// passed.
  /// <p>
  /// Note that this key is generally a hint, and may be ignored if you want to always load
  /// from the beginning.
  final Key requestedInitialKey;

  /// Requested number of items to load.
  /// <p>
  /// Note that this may be larger than available data.
  final int requestedLoadSize;

  /// Defines whether placeholders are enabled, and whether the total count passed to
  /// {@link LoadInitialCallback#onResult(List, int, int)} will be ignored.
  final bool placeholdersEnabled;

  LoadInitialParams(this.requestedInitialKey, this.requestedLoadSize,
      this.placeholdersEnabled);
}

/// Holder object for inputs to {@link #loadBefore(LoadParams, LoadCallback)}
/// and {@link #loadAfter(LoadParams, LoadCallback)}.
///
/// @param <Key> Type of data used to query Value types out of the DataSource.
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

/// Callback for ItemKeyedDataSource {@link #loadBefore(LoadParams, LoadCallback)}
/// and {@link #loadAfter(LoadParams, LoadCallback)} to return data.
/// <p>
/// A callback can be called only once, and will throw if called again.
/// <p>
/// It is always valid for a DataSource loading method that takes a callback to stash the
/// callback and call it later. This enables DataSources to be fully asynchronous, and to handle
/// temporary, recoverable error states (such as a network error that can be retried).
///
/// @param <Value> Type of items being loaded.
abstract class LoadCallback<Value> {
  /// Called to pass loaded data from a DataSource.
  /// <p>
  /// Call this method from your ItemKeyedDataSource's
  /// {@link #loadBefore(LoadParams, LoadCallback)} and
  /// {@link #loadAfter(LoadParams, LoadCallback)} methods to return data.
  /// <p>
  /// Call this from {@link #loadInitial(LoadInitialParams, LoadInitialCallback)} to
  /// initialize without counting available data, or supporting placeholders.
  /// <p>
  /// It is always valid to pass a different amount of data than what is requested. Pass an
  /// empty list if there is no more data to load.
  ///
  /// @param data List of items loaded from the ItemKeyedDataSource.
  void onResult(List<Value> data);
}

/// Callback for {@link #loadInitial(LoadInitialParams, LoadInitialCallback)}
/// to return data and, optionally, position/count information.
/// <p>
/// A callback can be called only once, and will throw if called again.
/// <p>
/// If you can compute the number of items in the data set before and after the loaded range,
/// call the three parameter {@link #onResult(List, int, int)} to pass that information. You
/// can skip passing this information by calling the single parameter {@link #onResult(List)},
/// either if it's difficult to compute, or if {@link LoadInitialParams#placeholdersEnabled} is
/// {@code false}, so the positioning information will be ignored.
/// <p>
/// It is always valid for a DataSource loading method that takes a callback to stash the
/// callback and call it later. This enables DataSources to be fully asynchronous, and to handle
/// temporary, recoverable error states (such as a network error that can be retried).
///
/// @param <Value> Type of items being loaded.
abstract class LoadInitialCallback<Value> extends LoadCallback<Value> {
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
  ///
  void onResultInitial(List<Value> data, int position, int totalCount);
}

class LoadInitialCallbackImpl<Key, Value> extends LoadInitialCallback<Value> {
  LoadCallbackHelper<Key, Value> mCallbackHelper;
  bool _mCountingEnabled;

  LoadInitialCallbackImpl(ItemKeyedDataSource<Key, Value> dataSource,
      bool countingEnabled, PageResultReceiver<Value> receiver) {
    this.mCallbackHelper =
        LoadCallbackHelper(dataSource, PageResult.INIT, receiver);
    this._mCountingEnabled = countingEnabled;
  }

  @override
  void onResult(List<Value> data) {
    if (!mCallbackHelper.dispatchInvalidResultIfInvalid()) {
      mCallbackHelper.dispatchResultToReceiver(PageResult<Value>(data, 0));
    }
  }

  @override
  void onResultInitial(List<Value> data, int position, int totalCount) {
    if (!mCallbackHelper.dispatchInvalidResultIfInvalid()) {
      LoadCallbackHelper.validateInitialLoadParams(data, position, totalCount);

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

class LoadCallbackImpl<Key, Value> extends LoadCallback<Value> {
  LoadCallbackHelper<Key, Value> _mCallbackHelper;

  LoadCallbackImpl(ItemKeyedDataSource<Key, Value> dataSource, int type,
      PageResultReceiver<Value> receiver) {
    _mCallbackHelper =
        LoadCallbackHelper<Key, Value>(dataSource, type, receiver);
  }

  @override
  void onResult(List<Value> data) {
    if (!_mCallbackHelper.dispatchInvalidResultIfInvalid()) {
      _mCallbackHelper.dispatchResultToReceiver(PageResult<Value>(data, 0));
    }
  }
}
