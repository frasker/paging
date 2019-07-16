import 'dart:math';

import 'contiguous_data_source.dart';
import 'contiguous_paged_list.dart';
import 'data_source.dart';
import 'paged_storage.dart';
import 'positional_data_source.dart';
import 'tiled_page_list.dart';

abstract class PagedList<T> {
  final BoundaryCallback<T> mBoundaryCallback;
  final Config _mConfig;
  final PagedStorage<T> mStorage;

  /// Last access location, in total position space (including offset).
  /// <p>
  /// Used by positional data
  /// sources to initialize loading near viewport
  int mLastLoad = 0;
  T mLastItem;

  int mRequiredRemainder;

  // if set to true, mBoundaryCallback is non-null, and should
  // be dispatched when nearby load has occurred
  bool mBoundaryCallbackBeginDeferred = false;
  bool mBoundaryCallbackEndDeferred = false;

  // lowest and highest index accessed by loadAround. Used to
  // decide when mBoundaryCallback should be dispatched

  static const num MAX_VALUE = 2147483647;
  static const num MIN_VALUE = -2147483648;

  int _mLowestIndexAccessed = MAX_VALUE;
  int _mHighestIndexAccessed = MIN_VALUE;

  bool _mDetached = false;

  final List<Callback> mCallbacks = List();

  PagedList(this.mStorage, this.mBoundaryCallback, this._mConfig) {
    mRequiredRemainder = _mConfig.prefetchDistance * 2 + _mConfig.pageSize;
  }

  static PagedList<T> create<K, T>(DataSource<K, T> dataSource,
      BoundaryCallback<T> boundaryCallback, Config config, K key) {
    if (dataSource.isContiguous() || !config.enablePlaceholders) {
      int lastLoad = ContiguousPagedList.LAST_LOAD_UNSPECIFIED;
      if (!dataSource.isContiguous()) {
        //noinspection unchecked
        dataSource = ((dataSource as PositionalDataSource<T>)
            .wrapAsContiguousWithoutPlaceholders()) as DataSource<K, T>;
        if (key != null) {
          lastLoad = key as int;
        }
      }
      ContiguousDataSource<K, T> configDataSource =
          dataSource as ContiguousDataSource<K, T>;
      return new ContiguousPagedList<K, T>(
          configDataSource, boundaryCallback, config, key, lastLoad);
    } else {
      return new TiledPagedList<T>(dataSource as PositionalDataSource<T>,
          boundaryCallback, config, (key != null) ? key as int : 0);
    }
  }

  /// Get the item in the list of loaded items at the provided index.
  ///
  /// @param index Index in the loaded item list. Must be >= 0, and &lt; {@link #size()}
  /// @return The item at the passed index, or null if a null placeholder is at the specified
  ///         position.
  ///
  /// @see #size()
  T get(int index) {
    T item = mStorage.get(index);
    if (item != null) {
      mLastItem = item;
    }
    return item;
  }

  /// Load adjacent items to passed index.
  ///
  /// @param index Index at which to load.
  void loadAround(int index) {
    if (index < 0 || index >= size()) {
      throw new IndexError(index, "Index: $index + Size: $size()");
    }

    mLastLoad = index + getPositionOffset();
    loadAroundInternal(index);

    _mLowestIndexAccessed = min(_mLowestIndexAccessed, index);
    _mHighestIndexAccessed = max(_mHighestIndexAccessed, index);

    /*
     * mLowestIndexAccessed / mHighestIndexAccessed have been updated, so check if we need to
     * dispatch boundary callbacks. Boundary callbacks are deferred until last items are loaded,
     * and accesses happen near the boundaries.
     *
     * Note: we post here, since RecyclerView may want to add items in response, and this
     * call occurs in PagedListAdapter bind.
     */
    tryDispatchBoundaryCallbacks(true);
  }

  void deferBoundaryCallbacks(
      final bool deferEmpty, final bool deferBegin, final bool deferEnd) {
    if (mBoundaryCallback == null) {
      throw new Exception("Can't defer BoundaryCallback, no instance");
    }

    /*
     * If lowest/highest haven't been initialized, set them to storage size,
     * since placeholders must already be computed by this point.
     *
     * This is just a minor optimization so that BoundaryCallback callbacks are sent immediately
     * if the initial load size is smaller than the prefetch window (see
     * TiledPagedListTest#boundaryCallback_immediate())
     */
    if (_mLowestIndexAccessed == MAX_VALUE) {
      _mLowestIndexAccessed = mStorage.size();
    }
    if (_mHighestIndexAccessed == MIN_VALUE) {
      _mHighestIndexAccessed = 0;
    }

    if (deferEmpty || deferBegin || deferEnd) {
      if (deferEmpty) {
        mBoundaryCallback.onZeroItemsLoaded();
      }

      // for other callbacks, mark deferred, and only dispatch if loadAround
      // has been called near to the position
      if (deferBegin) {
        mBoundaryCallbackBeginDeferred = true;
      }
      if (deferEnd) {
        mBoundaryCallbackEndDeferred = true;
      }
      tryDispatchBoundaryCallbacks(false);
    }
  }

  /// Call this when mLowest/HighestIndexAccessed are changed, or
  /// mBoundaryCallbackBegin/EndDeferred is set.
  void tryDispatchBoundaryCallbacks(bool post) {
    final bool dispatchBegin = mBoundaryCallbackBeginDeferred &&
        _mLowestIndexAccessed <= _mConfig.prefetchDistance;
    final bool dispatchEnd = mBoundaryCallbackEndDeferred &&
        _mHighestIndexAccessed >= size() - 1 - _mConfig.prefetchDistance;

    if (!dispatchBegin && !dispatchEnd) {
      return;
    }

    if (dispatchBegin) {
      mBoundaryCallbackBeginDeferred = false;
    }
    if (dispatchEnd) {
      mBoundaryCallbackEndDeferred = false;
    }
    if (post) {
      new Future(() {
        dispatchBoundaryCallbacks(dispatchBegin, dispatchEnd);
      });
    } else {
      dispatchBoundaryCallbacks(dispatchBegin, dispatchEnd);
    }
  }

  void dispatchBoundaryCallbacks(bool begin, bool end) {
    // safe to deref mBoundaryCallback here, since we only defer if mBoundaryCallback present
    if (begin) {
      //noinspection ConstantConditions
      mBoundaryCallback.onItemAtFrontLoaded(mStorage.getFirstLoadedItem());
    }
    if (end) {
      //noinspection ConstantConditions
      mBoundaryCallback.onItemAtEndLoaded(mStorage.getLastLoadedItem());
    }
  }

  void offsetAccessIndices(int offset) {
    // update last loadAround index
    mLastLoad += offset;

    // update access range
    _mLowestIndexAccessed += offset;
    _mHighestIndexAccessed += offset;
  }

  int size() {
    return mStorage.size();
  }

  bool isEmpty() {
    return size() == 0;
  }

  int getLoadedCount() {
    return mStorage.getLoadedCount();
  }

  bool isImmutable() {
    return isDetached();
  }

  PagedList<T> snapshot() {
    if (isImmutable()) {
      return this;
    }
    return SnapshotPagedList(this);
  }

  bool isContiguous();

  /// Return the Config used to construct this PagedList.
  ///
  /// @return the Config of this PagedList
  Config getConfig() {
    return _mConfig;
  }

  /// Return the DataSource that provides data to this PagedList.
  ///
  /// @return the DataSource of this PagedList.
  DataSource<dynamic, T> getDataSource();

  /// Return the key for the position passed most recently to {@link #loadAround(int)}.
  /// <p>
  /// When a PagedList is invalidated, you can pass the key returned by this function to initialize
  /// the next PagedList. This ensures (depending on load times) that the next PagedList that
  /// arrives will have data that overlaps. If you use {@link LivePagedListBuilder}, it will do
  /// this for you.
  ///
  /// @return Key of position most recently passed to {@link #loadAround(int)}.
  dynamic getLastKey();

  /// True if the PagedList has detached the DataSource it was loading from, and will no longer
  /// load new data.
  /// <p>
  /// A detached list is {@link #isImmutable() immutable}.
  ///
  /// @return True if the data source is detached.
  bool isDetached() {
    return _mDetached;
  }

  /// Detach the PagedList from its DataSource, and attempt to load no more data.
  /// <p>
  /// This is called automatically when a DataSource load returns <code>null</code>, which is a
  /// signal to stop loading. The «PagedList will continue to present existing data, but will not
  /// initiate new loads.
  void detach() {
    _mDetached = true;
  }

  /// Position offset of the data in the list.
  /// <p>
  /// If data is supplied by a {@link PositionalDataSource}, the item returned from
  /// <code>get(i)</code> has a position of <code>i + getPositionOffset()</code>.
  /// <p>
  /// If the DataSource is a {@link ItemKeyedDataSource} or {@link PageKeyedDataSource}, it
  /// doesn't use positions, returns 0.
  int getPositionOffset() {
    return mStorage.getPositionOffset();
  }

  void notifyInserted(int position, int count) {
    if (count != 0) {
      for (int i = mCallbacks.length - 1; i >= 0; i--) {
        final Callback callback = mCallbacks[i];
        if (callback != null) {
          callback.onInserted(position, count);
        }
      }
    }
  }

  void notifyChanged(int position, int count) {
    if (count != 0) {
      for (int i = mCallbacks.length - 1; i >= 0; i--) {
        final Callback callback = mCallbacks[i];

        if (callback != null) {
          callback.onChanged(position, count);
        }
      }
    }
  }

  /// Adds a callback, and issues updates since the previousSnapshot was created.
  /// <p>
  /// If previousSnapshot is passed, the callback will also immediately be dispatched any
  /// differences between the previous snapshot, and the current state. For example, if the
  /// previousSnapshot was of 5 nulls, 10 items, 5 nulls, and the current state was 5 nulls,
  /// 12 items, 3 nulls, the callback would immediately receive a call of
  /// <code>onChanged(14, 2)</code>.
  /// <p>
  /// This allows an observer that's currently presenting a snapshot to catch up to the most recent
  /// version, including any changes that may have been made.
  ///
  /// @param previousSnapshot Snapshot previously captured from this List, or null.
  /// @param callback Callback to dispatch to.
  ///
  /// @see #removeCallback(Callback)
  void addCallback(PagedList<T> previousSnapshot, Callback callback) {
    if (previousSnapshot != null && previousSnapshot != this) {
      if (previousSnapshot.isEmpty()) {
        if (!mStorage.isEmpty()) {
          // If snapshot is empty, diff is trivial - just notify number new items.
          // Note: occurs in async init, when snapshot taken before init page arrives
          callback.onInserted(0, mStorage.size());
        }
      } else {
        PagedList<T> storageSnapshot = previousSnapshot as PagedList<T>;

        //noinspection unchecked
        dispatchUpdatesSinceSnapshot(storageSnapshot, callback);
      }
    }

    // then add the new one
    mCallbacks.add(callback);
  }

  /// Removes a previously added callback.
  ///
  /// @param callback Callback, previously added.
  /// @see #addCallback(List, Callback)
  void removeCallback(Callback callback) {
    for (int i = mCallbacks.length - 1; i >= 0; i--) {
      final Callback currentCallback = mCallbacks[i];
      if (currentCallback == null || currentCallback == callback) {
        // found callback, or empty weak ref
        mCallbacks.remove(i);
      }
    }
  }

  void notifyRemoved(int position, int count) {
    if (count != 0) {
      for (int i = mCallbacks.length - 1; i >= 0; i--) {
        final Callback callback = mCallbacks[i];

        if (callback != null) {
          callback.onRemoved(position, count);
        }
      }
    }
  }

  /// Dispatch updates since the non-empty snapshot was taken.
  ///
  /// @param snapshot Non-empty snapshot.
  /// @param callback Callback for updates that have occurred since snapshot.
  void dispatchUpdatesSinceSnapshot(PagedList<T> snapshot, Callback callback);

  void loadAroundInternal(int index);
}

/// Callback signaling when content is loaded into the list.
/// <p>
/// Can be used to listen to items being paged in and out. These calls will be dispatched on
/// the executor defined by {@link Builder#setNotifyExecutor(Executor)}, which is generally
/// the main/UI thread.
abstract class Callback {
  /// Called when null padding items have been loaded to signal newly available data, or when
  /// data that hasn't been used in a while has been dropped, and swapped back to null.
  ///
  /// @param position Position of first newly loaded items, out of total number of items
  ///                 (including padded nulls).
  /// @param count    Number of items loaded.
  void onChanged(int position, int count);

  /// Called when new items have been loaded at the end or beginning of the list.
  ///
  /// @param position Position of the first newly loaded item (in practice, either
  ///                 <code>0</code> or <code>size - 1</code>.
  /// @param count    Number of items loaded.
  void onInserted(int position, int count);

  /// Called when items have been removed at the end or beginning of the list, and have not
  /// been replaced by padded nulls.
  ///
  /// @param position Position of the first newly loaded item (in practice, either
  ///                 <code>0</code> or <code>size - 1</code>.
  /// @param count    Number of items loaded.
  void onRemoved(int position, int count);
}

/// Configures how a PagedList loads content from its DataSource.
/// <p>
///  define custom loading behavior, such as
/// {@link setPageSize(int)}, which defines number of items loaded at a time}.
class Config {
  /// When {@link #maxSize} is set to {@code MAX_SIZE_UNBOUNDED}, the maximum number of items
  /// loaded is unbounded, and pages will never be dropped.
  static const int MAX_SIZE_UNBOUNDED = 2147483647;

  /// Size of each page loaded by the PagedList.
  int _pageSize = -1;

  /// Prefetch distance which defines how far ahead to load.
  /// <p>
  /// If this value is set to 50, the paged list will attempt to load 50 items in advance of
  /// data that's already been accessed.
  ///
  /// @see PagedList#loadAround(int)
  int _prefetchDistance = -1;

  /// Defines whether the PagedList may display null placeholders, if the DataSource provides
  /// them.
  bool _enablePlaceholders = true;

  /// Defines the maximum number of items that may be loaded into this pagedList before pages
  /// should be dropped.
  /// <p>
  /// {@link PageKeyedDataSource} does not currently support dropping pages - when
  /// loading from a {@code PageKeyedDataSource}, this value is ignored.
  ///
  /// @see #MAX_SIZE_UNBOUNDED
  /// @see Builder#setMaxSize(int)
  int _maxSize = MAX_SIZE_UNBOUNDED;

  /// Size hint for initial load of PagedList, often larger than a regular page.
  int _initialLoadSizeHint = -1;

  static final int DEFAULT_INITIAL_PAGE_MULTIPLIER = 3;

  Config(int pageSize, int prefetchDistance, bool enablePlaceholders,
      int initialLoadSizeHint, int maxSize) {
    if (pageSize < 1) {
      throw new Exception("Page size must be a positive number");
    }
    if (prefetchDistance < 0) {
      throw new Exception("prefetch distance must >= 0");
    }
    _prefetchDistance = prefetchDistance;
    _pageSize = pageSize;
    _enablePlaceholders = enablePlaceholders;

    if (initialLoadSizeHint < 1) {
      throw new Exception("Page size must be a positive number");
    }
    _initialLoadSizeHint = initialLoadSizeHint;
    if (maxSize < 2) {
      throw new Exception("maxSize must >= 2");
    }
    if (_prefetchDistance < 0) {
      _prefetchDistance = _pageSize;
    }
    if (_initialLoadSizeHint < 0) {
      _initialLoadSizeHint = _pageSize * DEFAULT_INITIAL_PAGE_MULTIPLIER;
    }
    if (!_enablePlaceholders && _prefetchDistance == 0) {
      throw new Exception("Placeholders and prefetch are the only ways" +
          " to trigger loading of more data in the PagedList, so either" +
          " placeholders must be enabled, or prefetch distance must be > 0.");
    }
    if (_maxSize != MAX_SIZE_UNBOUNDED) {
      if (_maxSize < _pageSize + _prefetchDistance * 2) {
        throw new Exception(
            "Maximum size must be at least pageSize + 2*prefetchDist, pageSize= $_pageSize, prefetchDist=  $_prefetchDistance , maxSize= $_maxSize");
      }
    }
  }

  int get pageSize => _pageSize;

  int get prefetchDistance => _prefetchDistance;

  bool get enablePlaceholders => _enablePlaceholders;

  int get initialLoadSizeHint => _initialLoadSizeHint;

  int get maxSize => _maxSize;
}

abstract class BoundaryCallback<T> {
  /// Called when zero items are returned from an initial load of the PagedList's data source.
  void onZeroItemsLoaded() {}

  /// Called when the item at the front of the PagedList has been loaded, and access has
  /// occurred within {@link Config#prefetchDistance} of it.
  /// <p>
  /// No more data will be prepended to the PagedList before this item.
  ///
  /// @param itemAtFront The first item of PagedList
  void onItemAtFrontLoaded(T itemAtFront) {}

  /// Called when the item at the end of the PagedList has been loaded, and access has
  /// occurred within {@link Config#prefetchDistance} of it.
  /// <p>
  /// No more data will be appended to the PagedList after this item.
  ///
  /// @param itemAtEnd The first item of PagedList
  void onItemAtEndLoaded(T itemAtEnd) {}
}

class SnapshotPagedList<T> extends PagedList<T> {
  bool mContiguous;
  dynamic mLastKey;
  DataSource<dynamic, T> mDataSource;

  SnapshotPagedList(PagedList<T> pagedList)
      : super(pagedList.mStorage.snapshot(), null, pagedList.getConfig()) {
    mDataSource = pagedList.getDataSource();
    mContiguous = pagedList.isContiguous();
    mLastLoad = pagedList.mLastLoad;
    mLastKey = pagedList.getLastKey();
  }

  @override
  void dispatchUpdatesSinceSnapshot(PagedList<T> snapshot, Callback callback) {}

  @override
  DataSource<dynamic, T> getDataSource() {
    return mDataSource;
  }

  @override
  getLastKey() {
    return mLastKey;
  }

  @override
  bool isContiguous() {
    return mContiguous;
  }

  @override
  bool isImmutable() {
    return true;
  }

  @override
  bool isDetached() {
    return true;
  }

  @override
  void loadAroundInternal(int index) {}
}
