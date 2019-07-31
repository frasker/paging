import 'dart:async';
import 'dart:math';
import 'contiguous_data_source.dart';
import 'data_source.dart';
import 'page_result.dart';
import 'wrapper_positional_data_source.dart';

/// Position-based data loader for a fixed-size, countable data set, supporting fixed-size loads at
/// arbitrary page positions.
/// <p>
/// Extend PositionalDataSource if you can load pages of a requested size at arbitrary
/// positions, and provide a fixed item count. If your data source can't support loading arbitrary
/// requested page sizes (e.g. when network page size constraints are only known at runtime), use
/// either {@link PageKeyedDataSource} or {@link ItemKeyedDataSource} instead.
/// <p>
/// Note that unless {@link PagedList.Config#enablePlaceholders placeholders are disabled}
/// PositionalDataSource requires counting the size of the data set. This allows pages to be tiled in
/// at arbitrary, non-contiguous locations based upon what the user observes in a {@link PagedList}.
/// If placeholders are disabled, initialize with the two parameter
/// {@link LoadInitialCallback#onResult(List, int)}.
///
/// @param <T> Type of items being loaded by the PositionalDataSource.
abstract class PositionalDataSource<T> extends DataSource<int, T> {
  void dispatchLoadInitial(
      bool acceptCount,
      int requestedStartPosition,
      int requestedLoadSize,
      int pageSize,
      PageResultReceiver<T> receiver,
      Completer<void> completer) {
    LoadInitialCallbackImpl<T> callback = new LoadInitialCallbackImpl<T>(
        this, acceptCount, pageSize, receiver, completer);

    LoadInitialParams params = new LoadInitialParams(
        requestedStartPosition, requestedLoadSize, pageSize, acceptCount);
    loadInitial(params, callback);
  }

  void dispatchLoadRange(int resultType, int startPosition, int count,
      PageResultReceiver<T> receiver) {
    LoadRangeCallback<T> callback =
        new LoadRangeCallbackImpl<T>(this, resultType, startPosition, receiver);
    if (count == 0) {
      callback.onResult(List<T>());
    } else {
      loadRange(new LoadRangeParams(startPosition, count), callback);
    }
  }

  /// Load initial list data.
  /// <p>
  /// This method is called to load the initial page(s) from the DataSource.
  /// <p>
  /// Result list must be a multiple of pageSize to enable efficient tiling.
  ///
  /// @param params Parameters for initial load, including requested start position, load size, and
  ///               page size.
  /// @param callback Callback that receives initial load data, including
  ///                 position and total data set size.
  void loadInitial(LoadInitialParams params, LoadInitialCallback<T> callback);

  /// Called to load a range of data from the DataSource.
  /// <p>
  /// This method is called to load additional pages from the DataSource after the
  /// LoadInitialCallback passed to dispatchLoadInitial has initialized a PagedList.
  /// <p>
  /// Unlike {@link #loadInitial(LoadInitialParams, LoadInitialCallback)}, this method must return
  /// the number of items requested, at the position requested.
  ///
  /// @param params Parameters for load, including start position and load size.
  /// @param callback Callback that receives loaded data.
  void loadRange(LoadRangeParams params, LoadRangeCallback<T> callback);

  /// Called to pass load finished from a DataSource.
  void onResultInitialFailed();

  @override
  bool isContiguous() {
    return false;
  }

  ContiguousDataSource<int, T> wrapAsContiguousWithoutPlaceholders() {
    return new ContiguousWithoutPlaceholdersWrapper<T>(this);
  }

  /// Helper for computing an initial position in
  /// {@link #loadInitial(LoadInitialParams, LoadInitialCallback)} when total data set size can be
  /// computed ahead of loading.
  /// <p>
  /// The value computed by this function will do bounds checking, page alignment, and positioning
  /// based on initial load size requested.
  /// <p>
  /// Example usage in a PositionalDataSource subclass:
  /// <pre>
  /// class ItemDataSource extends PositionalDataSource&lt;Item> {
  ///     private int computeCount() {
  ///         // actual count code here
  ///     }
  ///
  ///     private List&lt;Item> loadRangeInternal(int startPosition, int loadCount) {
  ///         // actual load code here
  ///     }
  ///
  ///     {@literal @}Override
  ///     public void loadInitial({@literal @}NonNull LoadInitialParams params,
  ///             {@literal @}NonNull LoadInitialCallback&lt;Item> callback) {
  ///         int totalCount = computeCount();
  ///         int position = computeInitialLoadPosition(params, totalCount);
  ///         int loadSize = computeInitialLoadSize(params, position, totalCount);
  ///         callback.onResult(loadRangeInternal(position, loadSize), position, totalCount);
  ///     }
  ///
  ///     {@literal @}Override
  ///     public void loadRange({@literal @}NonNull LoadRangeParams params,
  ///             {@literal @}NonNull LoadRangeCallback&lt;Item> callback) {
  ///         callback.onResult(loadRangeInternal(params.startPosition, params.loadSize));
  ///     }
  /// }</pre>
  ///
  /// @param params Params passed to {@link #loadInitial(LoadInitialParams, LoadInitialCallback)},
  ///               including page size, and requested start/loadSize.
  /// @param totalCount Total size of the data set.
  /// @return Position to start loading at.
  ///
  /// @see #computeInitialLoadSize(LoadInitialParams, int, int)
  static int computeInitialLoadPosition(
      LoadInitialParams params, int totalCount) {
    int position = params.requestedStartPosition;
    int initialLoadSize = params.requestedLoadSize;
    int pageSize = params.pageSize;

    int pageStart = position ~/ pageSize * pageSize;

    // maximum start pos is that which will encompass end of list
    int maximumLoadPage =
        ((totalCount - initialLoadSize + pageSize - 1) ~/ pageSize) * pageSize;
    pageStart = min(maximumLoadPage, pageStart);

    // minimum start position is 0
    pageStart = max(0, pageStart);

    return pageStart;
  }

  /// Helper for computing an initial load size in
  /// {@link #loadInitial(LoadInitialParams, LoadInitialCallback)} when total data set size can be
  /// computed ahead of loading.
  /// <p>
  /// This function takes the requested load size, and bounds checks it against the value returned
  /// by {@link #computeInitialLoadPosition(LoadInitialParams, int)}.
  /// <p>
  /// Example usage in a PositionalDataSource subclass:
  /// <pre>
  /// class ItemDataSource extends PositionalDataSource&lt;Item> {
  ///     private int computeCount() {
  ///         // actual count code here
  ///     }
  ///
  ///     private List&lt;Item> loadRangeInternal(int startPosition, int loadCount) {
  ///         // actual load code here
  ///     }
  ///
  ///     {@literal @}Override
  ///     public void loadInitial({@literal @}NonNull LoadInitialParams params,
  ///             {@literal @}NonNull LoadInitialCallback&lt;Item> callback) {
  ///         int totalCount = computeCount();
  ///         int position = computeInitialLoadPosition(params, totalCount);
  ///         int loadSize = computeInitialLoadSize(params, position, totalCount);
  ///         callback.onResult(loadRangeInternal(position, loadSize), position, totalCount);
  ///     }
  ///
  ///     {@literal @}Override
  ///     public void loadRange({@literal @}NonNull LoadRangeParams params,
  ///             {@literal @}NonNull LoadRangeCallback&lt;Item> callback) {
  ///         callback.onResult(loadRangeInternal(params.startPosition, params.loadSize));
  ///     }
  /// }</pre>
  ///
  /// @param params Params passed to {@link #loadInitial(LoadInitialParams, LoadInitialCallback)},
  ///               including page size, and requested start/loadSize.
  /// @param initialLoadPosition Value returned by
  ///                          {@link #computeInitialLoadPosition(LoadInitialParams, int)}
  /// @param totalCount Total size of the data set.
  /// @return Number of items to load.
  ///
  /// @see #computeInitialLoadPosition(LoadInitialParams, int)
  static int computeInitialLoadSize(
      LoadInitialParams params, int initialLoadPosition, int totalCount) {
    return min(totalCount - initialLoadPosition, params.requestedLoadSize);
  }

  @override
  PositionalDataSource<ToValue> mapByPage<ToValue>(
      List<ToValue> Function(List<T> data) func) {
    return WrapperPositionalDataSource<T, ToValue>(this, func);
  }

  @override
  PositionalDataSource<ToValue> map<ToValue>(ToValue Function(T data) func) {
    return mapByPage<ToValue>(DataSource.createListFunction<T, ToValue>(func));
  }
}

/// Holder object for inputs to {@link #loadInitial(LoadInitialParams, LoadInitialCallback)}.
class LoadInitialParams {
  /// Initial load position requested.
  /// <p>
  /// Note that this may not be within the bounds of your data set, it may need to be adjusted
  /// before you execute your load.
  final int requestedStartPosition;

  /// Requested number of items to load.
  /// <p>
  /// Note that this may be larger than available data.
  final int requestedLoadSize;

  /// Defines page size acceptable for return values.
  /// <p>
  /// List of items passed to the callback must be an integer multiple of page size.
  final int pageSize;

  /// Defines whether placeholders are enabled, and whether the total count passed to
  /// {@link LoadInitialCallback#onResult(List, int, int)} will be ignored.
  final bool placeholdersEnabled;

  LoadInitialParams(this.requestedStartPosition, this.requestedLoadSize,
      this.pageSize, this.placeholdersEnabled);
}

/// Holder object for inputs to {@link #loadRange(LoadRangeParams, LoadRangeCallback)}.
class LoadRangeParams {
  /// Start position of data to load.
  /// <p>
  /// Returned data must start at this position.
  final int startPosition;

  /// Number of items to load.
  /// <p>
  /// Returned data must be of this size, unless at end of the list.
  final int loadSize;

  LoadRangeParams(this.startPosition, this.loadSize);
}

/// Callback for {@link #loadInitial(LoadInitialParams, LoadInitialCallback)}
/// to return data, position, and count.
/// <p>
/// A callback should be called only once, and may throw if called again.
/// <p>
/// It is always valid for a DataSource loading method that takes a callback to stash the
/// callback and call it later. This enables DataSources to be fully asynchronous, and to handle
/// temporary, recoverable error states (such as a network error that can be retried).
///
/// @param <T> Type of items being loaded.
abstract class LoadInitialCallback<T> {
  /// Called to pass initial load state from a DataSource.
  /// <p>
  /// Call this method from your DataSource's {@code loadInitial} function to return data,
  /// and inform how many placeholders should be shown before and after. If counting is cheap
  /// to compute (for example, if a network load returns the information regardless), it's
  /// recommended to pass the total size to the totalCount parameter. If placeholders are not
  /// requested (when {@link LoadInitialParams#placeholdersEnabled} is false), you can instead
  /// call {@link #onResult(List, int)}.
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
  void onResultInitial(List<T> data, int position, int totalCount);

  /// Called to pass initial load state from a DataSource without total count,
  /// when placeholders aren't requested.
  /// <p class="note"><strong>Note:</strong> This method can only be called when placeholders
  /// are disabled ({@link LoadInitialParams#placeholdersEnabled} is false).
  /// <p>
  /// Call this method from your DataSource's {@code loadInitial} function to return data,
  /// if position is known but total size is not. If placeholders are requested, call the three
  /// parameter variant: {@link #onResult(List, int, int)}.
  ///
  /// @param data List of items loaded from the DataSource. If this is empty, the DataSource
  ///             is treated as empty, and no further loads will occur.
  /// @param position Position of the item at the front of the list. If there are {@code N}
  ///                 items before the items in data that can be provided by this DataSource,
  ///                 pass {@code N}.
  void onResult(List<T> data, int position);

  /// Called to pass load finished from a DataSource.
  void onResultInitialFailed();
}

/// Callback for PositionalDataSource {@link #loadRange(LoadRangeParams, LoadRangeCallback)}
/// to return data.
/// <p>
/// A callback should be called only once, and may throw if called again.
/// <p>
/// It is always valid for a DataSource loading method that takes a callback to stash the
/// callback and call it later. This enables DataSources to be fully asynchronous, and to handle
/// temporary, recoverable error states (such as a network error that can be retried).
///
/// @param <T> Type of items being loaded.
abstract class LoadRangeCallback<T> {
  /// Called to pass loaded data from {@link #loadRange(LoadRangeParams, LoadRangeCallback)}.
  ///
  /// @param data List of items loaded from the DataSource. Must be same size as requested,
  ///             unless at end of list.
  void onResult(List<T> data);
}

class LoadInitialCallbackImpl<Value> extends LoadInitialCallback<Value> {
  LoadCallbackHelper<int, Value> mCallbackHelper;
  bool _mCountingEnabled;
  int mPageSize;
  Completer<void> _mCompleter;

  LoadInitialCallbackImpl(
      PositionalDataSource<Value> dataSource,
      bool countingEnabled,
      int pageSize,
      PageResultReceiver<Value> receiver,
      Completer<void> completer) {
    this.mCallbackHelper =
        LoadCallbackHelper<int, Value>(dataSource, PageResult.INIT, receiver);
    this._mCountingEnabled = countingEnabled;
    mPageSize = pageSize;
    _mCompleter = completer;
    if (mPageSize < 1) {
      throw new Exception("Page size must be non-negative");
    }
  }

  @override
  void onResult(List<Value> data, int position) {
    if (!mCallbackHelper.dispatchInvalidResultIfInvalid()) {
      if (position < 0) {
        throw new Exception("Position must be non-negative");
      }
      if (data.isEmpty && position != 0) {
        throw new Exception(
            "Initial result cannot be empty if items are present in data set.");
      }
      if (_mCountingEnabled) {
        throw new Exception("Placeholders requested, but totalCount not" +
            " provided. Please call the three-parameter onResult method, or" +
            " disable placeholders in the PagedList.Config");
      }
      mCallbackHelper
          .dispatchResultToReceiver(PageResult<Value>(data, position));
      _mCompleter.complete();
    } else {
      _mCompleter.completeError(null);
    }
  }

  @override
  void onResultInitial(List<Value> data, int position, int totalCount) {
    if (!mCallbackHelper.dispatchInvalidResultIfInvalid()) {
      LoadCallbackHelper.validateInitialLoadParams(data, position, totalCount);

      if (position + data.length != totalCount &&
          data.length % mPageSize != 0) {
        throw new Exception("PositionalDataSource requires initial load" +
            " size to be a multiple of page size to support internal tiling." +
            " loadSize ${data.length} , position $position, totalCount $totalCount , pageSize $mPageSize");
      }

      if (_mCountingEnabled) {
        int trailingUnloadedCount = totalCount - position - data.length;
        mCallbackHelper.dispatchResultToReceiver(PageResult<Value>(data, 0,
            leadingNulls: position, trailingNulls: trailingUnloadedCount));
      } else {
        // Only occurs when wrapped as contiguous
        mCallbackHelper
            .dispatchResultToReceiver(PageResult<Value>(data, position));
      }
      _mCompleter.complete();
    } else {
      _mCompleter.completeError(null);
    }
  }

  @override
  void onResultInitialFailed() {
    _mCompleter.completeError(null);
  }
}

class LoadRangeCallbackImpl<Value> extends LoadRangeCallback<Value> {
  LoadCallbackHelper<int, Value> mCallbackHelper;
  int mPositionOffset;

  LoadRangeCallbackImpl(PositionalDataSource<Value> dataSource, int resultType,
      int positionOffset, PageResultReceiver<Value> receiver) {
    mCallbackHelper =
        new LoadCallbackHelper<int, Value>(dataSource, resultType, receiver);
    mPositionOffset = positionOffset;
  }

  @override
  void onResult(List<Value> data) {
    if (!mCallbackHelper.dispatchInvalidResultIfInvalid()) {
      mCallbackHelper.dispatchResultToReceiver(
          new PageResult<Value>(data, mPositionOffset));
    }
  }
}

class ContiguousWithoutPlaceholdersWrapper<Value>
    extends ContiguousDataSource<int, Value> {
  final PositionalDataSource<Value> mSource;

  ContiguousWithoutPlaceholdersWrapper(this.mSource);

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
  void dispatchLoadAfter(int currentEndIndex, Value currentEndItem,
      int pageSize, PageResultReceiver<Value> receiver) {
    int startIndex = currentEndIndex + 1;
    mSource.dispatchLoadRange(
        PageResult.APPEND, startIndex, pageSize, receiver);
  }

  @override
  void dispatchLoadBefore(int currentBeginIndex, Value currentBeginItem,
      int pageSize, PageResultReceiver<Value> receiver) {
    int startIndex = currentBeginIndex - 1;
    if (startIndex < 0) {
      // trigger empty list load
      mSource.dispatchLoadRange(PageResult.PREPEND, startIndex, 0, receiver);
    } else {
      int loadSize = min(pageSize, startIndex + 1);
      startIndex = startIndex - loadSize + 1;
      mSource.dispatchLoadRange(
          PageResult.PREPEND, startIndex, loadSize, receiver);
    }
  }

  @override
  void dispatchLoadInitial(
      int position,
      int initialLoadSize,
      int pageSize,
      bool enablePlaceholders,
      PageResultReceiver<Value> receiver,
      Completer<void> completer) {
    final int convertPosition = position == null ? 0 : position;

    // Note enablePlaceholders will be false here, but we don't have a way to communicate
    // this to PositionalDataSource. This is fine, because only the list and its position
    // offset will be consumed by the LoadInitialCallback.
    mSource.dispatchLoadInitial(
        false, convertPosition, initialLoadSize, pageSize, receiver, completer);
  }

  @override
  int getKey(int position, Value item) {
    return position;
  }

  @override
  DataSource<int, ToValue> map<ToValue>(ToValue Function(Value data) func) {
    throw new Exception("Inaccessible inner type doesn't support map op");
  }

  @override
  DataSource<int, ToValue> mapByPage<ToValue>(
      List<ToValue> Function(List<Value> data) func) {
    throw new Exception("Inaccessible inner type doesn't support map op");
  }
}
