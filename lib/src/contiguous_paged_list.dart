import 'dart:math';

import 'contiguous_data_source.dart';
import 'data_source.dart';
import 'page_list.dart';
import 'page_result.dart';
import 'paged_storage.dart';

class ContiguousPagedList<K, V> extends PagedList<V>
    implements PagedStorageCallback {
  ContiguousDataSource<K, V> mDataSource;

  static final int READY_TO_FETCH = 0;
  static final int FETCHING = 1;
  static final int DONE_FETCHING = 2;

  int mPrependWorkerState = READY_TO_FETCH;

  int mAppendWorkerState = READY_TO_FETCH;

  int mPrependItemsRequested = 0;
  int mAppendItemsRequested = 0;

  bool mReplacePagesWithNulls = false;

  bool mShouldTrim;

  static final int LAST_LOAD_UNSPECIFIED = -1;

  PageResultReceiver<V> mReceiver;

  ContiguousPagedList(ContiguousDataSource<K, V> dataSource,
      BoundaryCallback<V> boundaryCallback, Config config, K key, int lastLoad)
      : super(PagedStorage<V>(), boundaryCallback, config) {
    mDataSource = dataSource;
    mLastLoad = lastLoad;

    mReceiver = MyPageResultReceiver<V>(this);

    if (mDataSource.invalid) {
      detach();
    } else {
      mDataSource.dispatchLoadInitial(key, getConfig().initialLoadSizeHint,
          getConfig().pageSize, getConfig().enablePlaceholders, mReceiver);
    }
    mShouldTrim = mDataSource.supportsPageDropping() &&
        getConfig().maxSize != Config.MAX_SIZE_UNBOUNDED;
  }

  @override
  void dispatchUpdatesSinceSnapshot(
      PagedList<V> pagedListSnapshot, Callback callback) {
    final PagedStorage<V> snapshot = pagedListSnapshot.mStorage;

    final int newlyAppended =
        mStorage.getNumberAppended() - snapshot.getNumberAppended();
    final int newlyPrepended =
        mStorage.getNumberPrepended() - snapshot.getNumberPrepended();

    final int previousTrailing = snapshot.getTrailingNullCount();
    final int previousLeading = snapshot.getLeadingNullCount();

    // Validate that the snapshot looks like a previous version of this list - if it's not,
    // we can't be sure we'll dispatch callbacks safely
    if (snapshot.isEmpty() ||
        newlyAppended < 0 ||
        newlyPrepended < 0 ||
        mStorage.getTrailingNullCount() !=
            max(previousTrailing - newlyAppended, 0) ||
        mStorage.getLeadingNullCount() !=
            max(previousLeading - newlyPrepended, 0) ||
        (mStorage.getStorageCount() !=
            snapshot.getStorageCount() + newlyAppended + newlyPrepended)) {
      throw new Exception("Invalid snapshot provided - doesn't appear" +
          " to be a snapshot of this PagedList");
    }

    if (newlyAppended != 0) {
      final int changedCount = min(previousTrailing, newlyAppended);
      final int addedCount = newlyAppended - changedCount;

      final int endPosition =
          snapshot.getLeadingNullCount() + snapshot.getStorageCount();
      if (changedCount != 0) {
        callback.onChanged(endPosition, changedCount);
      }
      if (addedCount != 0) {
        callback.onInserted(endPosition + changedCount, addedCount);
      }
    }
    if (newlyPrepended != 0) {
      final int changedCount = min(previousLeading, newlyPrepended);
      final int addedCount = newlyPrepended - changedCount;

      if (changedCount != 0) {
        callback.onChanged(previousLeading, changedCount);
      }
      if (addedCount != 0) {
        callback.onInserted(0, addedCount);
      }
    }
  }

  static int getPrependItemsRequested(
      int prefetchDistance, int index, int leadingNulls) {
    return prefetchDistance - (index - leadingNulls);
  }

  static int getAppendItemsRequested(
      int prefetchDistance, int index, int itemsBeforeTrailingNulls) {
    return index + prefetchDistance + 1 - itemsBeforeTrailingNulls;
  }

  @override
  DataSource<dynamic, V> getDataSource() {
    return mDataSource;
  }

  @override
  dynamic getLastKey() {
    return mDataSource.getKey(mLastLoad, mLastItem);
  }

  @override
  bool isContiguous() {
    return true;
  }

  @override
  void loadAroundInternal(int index) {
    int prependItems = getPrependItemsRequested(
        getConfig().prefetchDistance, index, mStorage.getLeadingNullCount());
    int appendItems = getAppendItemsRequested(getConfig().prefetchDistance,
        index, mStorage.getLeadingNullCount() + mStorage.getStorageCount());

    mPrependItemsRequested = max(prependItems, mPrependItemsRequested);
    if (mPrependItemsRequested > 0) {
      _schedulePrepend();
    }

    mAppendItemsRequested = max(appendItems, mAppendItemsRequested);
    if (mAppendItemsRequested > 0) {
      _scheduleAppend();
    }
  }

  void _schedulePrepend() {
    if (mPrependWorkerState != READY_TO_FETCH) {
      return;
    }
    mPrependWorkerState = FETCHING;

    final int position =
        mStorage.getLeadingNullCount() + mStorage.getPositionOffset();

    // safe to access first item here - mStorage can't be empty if we're prepending
    final V item = mStorage.getFirstLoadedItem();
    Future(() {
      if (isDetached()) {
        return;
      }
      if (mDataSource.invalid) {
        detach();
      } else {
        mDataSource.dispatchLoadBefore(
            position, item, getConfig().pageSize, mReceiver);
      }
    });
  }

  void _scheduleAppend() {
    if (mAppendWorkerState != READY_TO_FETCH) {
      return;
    }
    mAppendWorkerState = FETCHING;

    final int position = mStorage.getLeadingNullCount() +
        mStorage.getStorageCount() -
        1 +
        mStorage.getPositionOffset();

    // safe to access first item here - mStorage can't be empty if we're appending
    final V item = mStorage.getLastLoadedItem();
    Future(() {
      if (isDetached()) {
        return;
      }
      if (mDataSource.invalid) {
        detach();
      } else {
        mDataSource.dispatchLoadAfter(
            position, item, getConfig().pageSize, mReceiver);
      }
    });
  }

  @override
  void onEmptyAppend() {
    mAppendWorkerState = DONE_FETCHING;
  }

  @override
  void onEmptyPrepend() {
    mPrependWorkerState = DONE_FETCHING;
  }

  @override
  void onInitialized(int count) {
    notifyInserted(0, count);
    // simple heuristic to decide if, when dropping pages, we should replace with placeholders
    mReplacePagesWithNulls = mStorage.getLeadingNullCount() > 0 ||
        mStorage.getTrailingNullCount() > 0;
  }

  @override
  void onPageAppended(int endPosition, int changedCount, int addedCount) {
    // consider whether to post more work, now that a page is fully appended
    mAppendItemsRequested = mAppendItemsRequested - changedCount - addedCount;
    mAppendWorkerState = READY_TO_FETCH;
    if (mAppendItemsRequested > 0) {
      // not done appending, keep going
      _scheduleAppend();
    }

    // finally dispatch callbacks, after append may have already been scheduled
    notifyChanged(endPosition, changedCount);
    notifyInserted(endPosition + changedCount, addedCount);
  }

  @override
  void onPageInserted(int start, int count) {
    throw new Exception("Tiled callback on ContiguousPagedList");
  }

  @override
  void onPagePlaceholderInserted(int pageIndex) {
    throw new Exception("Tiled callback on ContiguousPagedList");
  }

  @override
  void onPagePrepended(int leadingNulls, int changedCount, int addedCount) {
    // consider whether to post more work, now that a page is fully prepended
    mPrependItemsRequested = mPrependItemsRequested - changedCount - addedCount;
    mPrependWorkerState = READY_TO_FETCH;
    if (mPrependItemsRequested > 0) {
      // not done prepending, keep going
      _schedulePrepend();
    }

    // finally dispatch callbacks, after prepend may have already been scheduled
    notifyChanged(leadingNulls, changedCount);
    notifyInserted(0, addedCount);

    offsetAccessIndices(addedCount);
  }

  @override
  void onPagesRemoved(int startOfDrops, int count) {
    notifyRemoved(startOfDrops, count);
  }

  @override
  void onPagesSwappedToPlaceholder(int startOfDrops, int count) {
    notifyChanged(startOfDrops, count);
  }
}

class MyPageResultReceiver<V> implements PageResultReceiver<V> {
  ContiguousPagedList pagedList;

  MyPageResultReceiver(this.pagedList);

  @override
  void onPageResult(int resultType, PageResult pageResult) {
    if (pageResult.isInvalid()) {
      pagedList.detach();
      return;
    }

    if (pagedList.isDetached()) {
      // No op, have detached
      return;
    }

    List<V> page = pageResult.page;
    if (resultType == PageResult.INIT) {
      pagedList.mStorage.initWithCallback(pageResult.leadingNulls, page,
          pageResult.trailingNulls, pageResult.positionOffset, pagedList);
      if (pagedList.mLastLoad == ContiguousPagedList.LAST_LOAD_UNSPECIFIED) {
        // Because the ContiguousPagedList wasn't initialized with a last load position,
        // initialize it to the middle of the initial load
        pagedList.mLastLoad = (pageResult.leadingNulls +
                pageResult.positionOffset +
                page.length / 2)
            .toInt();
      }
    } else {
      // if we end up trimming, we trim from side that's furthest from most recent access
      bool trimFromFront =
          pagedList.mLastLoad > pagedList.mStorage.getMiddleOfLoadedRange();

      // is the new page big enough to warrant pre-trimming (i.e. dropping) it?
      bool skipNewPage = pagedList.mShouldTrim &&
          pagedList.mStorage.shouldPreTrimNewPage(pagedList.getConfig().maxSize,
              pagedList.mRequiredRemainder, page.length);

      if (resultType == PageResult.APPEND) {
        if (skipNewPage && !trimFromFront) {
          // don't append this data, drop it
          pagedList.mAppendItemsRequested = 0;
          pagedList.mAppendWorkerState = ContiguousPagedList.READY_TO_FETCH;
        } else {
          pagedList.mStorage.appendPage(page, pagedList);
        }
      } else if (resultType == PageResult.PREPEND) {
        if (skipNewPage && trimFromFront) {
          // don't append this data, drop it
          pagedList.mPrependItemsRequested = 0;
          pagedList.mPrependWorkerState = ContiguousPagedList.READY_TO_FETCH;
        } else {
          pagedList.mStorage.prependPage(page, pagedList);
        }
      } else {
        throw new Exception("unexpected resultType $resultType");
      }

      if (pagedList.mShouldTrim) {
        if (trimFromFront) {
          if (pagedList.mPrependWorkerState != ContiguousPagedList.FETCHING) {
            if (pagedList.mStorage.trimFromFront(
                pagedList.mReplacePagesWithNulls,
                pagedList.getConfig().maxSize,
                pagedList.mRequiredRemainder,
                pagedList)) {
              // trimmed from front, ensure we can fetch in that dir
              pagedList.mPrependWorkerState =
                  ContiguousPagedList.READY_TO_FETCH;
            }
          }
        } else {
          if (pagedList.mAppendWorkerState != ContiguousPagedList.FETCHING) {
            if (pagedList.mStorage.trimFromEnd(
                pagedList.mReplacePagesWithNulls,
                pagedList.getConfig().maxSize,
                pagedList.mRequiredRemainder,
                pagedList)) {
              pagedList.mAppendWorkerState = ContiguousPagedList.READY_TO_FETCH;
            }
          }
        }
      }
    }

    if (pagedList.mBoundaryCallback != null) {
      bool deferEmpty = pagedList.mStorage.size() == 0;
      bool deferBegin = !deferEmpty &&
          resultType == PageResult.PREPEND &&
          pageResult.page.length == 0;
      bool deferEnd = !deferEmpty &&
          resultType == PageResult.APPEND &&
          pageResult.page.length == 0;
      pagedList.deferBoundaryCallbacks(deferEmpty, deferBegin, deferEnd);
    }
  }
}
