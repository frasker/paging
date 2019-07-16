import 'dart:math';

import 'package:paging/src/data_source.dart';

import 'page_list.dart';
import 'page_result.dart';
import 'paged_storage.dart';
import 'positional_data_source.dart';

class TiledPagedList<T> extends PagedList<T> with PagedStorageCallback {
  PositionalDataSource<T> mDataSource;

  PageResultReceiver<T> mReceiver;

  TiledPagedList(PositionalDataSource<T> dataSource,
      BoundaryCallback<T> boundaryCallback, Config config, int position)
      : super(PagedStorage<T>(), boundaryCallback, config) {
    mReceiver = _MyPageResultReceiver<T>(this);

    mDataSource = dataSource;

    final int pageSize = getConfig().pageSize;
    mLastLoad = position;

    if (mDataSource.invalid) {
      detach();
    } else {
      final int firstLoadSize =
          (max(getConfig().initialLoadSizeHint / pageSize, 2)) * pageSize;

      final int idealStart = position - firstLoadSize ~/ 2;
      final int roundedPageStart = max(0, idealStart ~/ pageSize * pageSize);

      mDataSource.dispatchLoadInitial(
          true, roundedPageStart, firstLoadSize, pageSize, mReceiver);
    }
  }

  @override
  bool isContiguous() {
    return false;
  }

  @override
  DataSource<int, T> getDataSource() {
    return mDataSource;
  }

  @override
  getLastKey() {
    return mLastLoad;
  }

  @override
  void dispatchUpdatesSinceSnapshot(
      PagedList<T> pagedListSnapshot, Callback callback) {
    //noinspection UnnecessaryLocalVariable
    final PagedStorage<T> snapshot = pagedListSnapshot.mStorage;

    if (snapshot.isEmpty() || mStorage.size() != snapshot.size()) {
      throw new Exception("Invalid snapshot provided - doesn't appear" +
          " to be a snapshot of this PagedList");
    }

    // loop through each page and signal the callback for any pages that are present now,
    // but not in the snapshot.
    final int pageSize = getConfig().pageSize;
    final int leadingNullPages = mStorage.getLeadingNullCount() ~/ pageSize;
    final int pageCount = mStorage.getPageCount();
    for (int i = 0; i < pageCount; i++) {
      int pageIndex = i + leadingNullPages;
      int updatedPages = 0;
      // count number of consecutive pages that were added since the snapshot...
      while (updatedPages < mStorage.getPageCount() &&
          mStorage.hasPage(pageSize, pageIndex + updatedPages) &&
          !snapshot.hasPage(pageSize, pageIndex + updatedPages)) {
        updatedPages++;
      }
      // and signal them all at once to the callback
      if (updatedPages > 0) {
        callback.onChanged(pageIndex * pageSize, pageSize * updatedPages);
        i += updatedPages - 1;
      }
    }
  }

  @override
  void loadAroundInternal(int index) {
    mStorage.allocatePlaceholders(
        index, getConfig().prefetchDistance, getConfig().pageSize, this);
  }

  @override
  void onEmptyAppend() {
    throw new Exception("Contiguous callback on TiledPagedList");
  }

  @override
  void onEmptyPrepend() {
    throw new Exception("Contiguous callback on TiledPagedList");
  }

  @override
  void onInitialized(int count) {
    notifyInserted(0, count);
  }

  @override
  void onPageAppended(int endPosition, int changed, int added) {
    throw new Exception("Contiguous callback on TiledPagedList");
  }

  @override
  void onPageInserted(int start, int count) {
    notifyChanged(start, count);
  }

  @override
  void onPagePlaceholderInserted(int pageIndex) {
    Future(() {
      if (isDetached()) {
        return;
      }
      final int pageSize = getConfig().pageSize;

      if (mDataSource.invalid) {
        detach();
      } else {
        int startPosition = pageIndex * pageSize;
        int count = min(pageSize, mStorage.size() - startPosition);
        mDataSource.dispatchLoadRange(
            PageResult.TILE, startPosition, count, mReceiver);
      }
    });
  }

  @override
  void onPagePrepended(int leadingNulls, int changed, int added) {
    throw new Exception("Contiguous callback on TiledPagedList");
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

class _MyPageResultReceiver<T> extends PageResultReceiver<T> {
  final TiledPagedList<T> _tiledPagedList;

  _MyPageResultReceiver(this._tiledPagedList);

  @override
  void onPageResult(int type, PageResult<T> pageResult) {
    if (pageResult.isInvalid()) {
      _tiledPagedList.detach();
      return;
    }

    if (_tiledPagedList.isDetached()) {
      // No op, have detached
      return;
    }

    if (type != PageResult.INIT && type != PageResult.TILE) {
      throw new Exception("unexpected resultType $type");
    }

    List<T> page = pageResult.page;
    if (_tiledPagedList.mStorage.getPageCount() == 0) {
      _tiledPagedList.mStorage.initAndSplit(
          pageResult.leadingNulls,
          page,
          pageResult.trailingNulls,
          pageResult.positionOffset,
          _tiledPagedList.getConfig().pageSize,
          _tiledPagedList);
    } else {
      _tiledPagedList.mStorage.tryInsertPageAndTrim(
          pageResult.positionOffset,
          page,
          _tiledPagedList.mLastLoad,
          _tiledPagedList.getConfig().maxSize,
          _tiledPagedList.mRequiredRemainder,
          _tiledPagedList);
    }

    if (_tiledPagedList.mBoundaryCallback != null) {
      bool deferEmpty = _tiledPagedList.mStorage.size() == 0;
      bool deferBegin = !deferEmpty &&
          pageResult.leadingNulls == 0 &&
          pageResult.positionOffset == 0;
      int size = _tiledPagedList.size();
      bool deferEnd = !deferEmpty &&
          ((type == PageResult.INIT && pageResult.trailingNulls == 0) ||
              (type == PageResult.TILE &&
                  (pageResult.positionOffset +
                          _tiledPagedList.getConfig().pageSize >=
                      size)));
      _tiledPagedList.deferBoundaryCallbacks(deferEmpty, deferBegin, deferEnd);
    }
  }
}
