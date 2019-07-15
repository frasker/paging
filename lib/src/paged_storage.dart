import 'dart:math';

import 'page_list.dart';

class PagedStorage<T> {
  /// Lists instances are compared (with instance equality) to PLACEHOLDER_LIST to check if an item
  /// in that position is already loading. We use a singleton placeholder list that is distinct
  /// from Collections.emptyList() for safety.
  final List<T> PLACEHOLDER_LIST = List<T>();

  int mLeadingNullCount;

  /// List of pages in storage.
  ///
  /// Two storage modes:
  ///
  /// Contiguous - all content in mPages is valid and loaded, but may return false from isTiled().
  ///     Safe to access any item in any page.
  ///
  /// Non-contiguous - mPages may have nulls or a placeholder page, isTiled() always returns true.
  ///     mPages may have nulls, or placeholder (empty) pages while content is loading.
  List<List<T>> mPages;

  int mTrailingNullCount;
  int mPositionOffset;

  /// Number of loaded items held by {@link #mPages}. When tiling, doesn't count unloaded pages in
  /// {@link #mPages}. If tiling is disabled, same as {@link #mStorageCount}.
  ///
  /// This count is the one used for trimming.
  int mLoadedCount;

  /// Number of items represented by {@link #mPages}. If tiling is enabled, unloaded items in
  /// {@link #mPages} may be null, but this value still counts them.
  int mStorageCount;

  // If mPageSize > 0, tiling is enabled, 'mPages' may have gaps, and leadingPages is set
  int mPageSize;

  int mNumberPrepended;
  int mNumberAppended;

  PagedStorage() {
    mLeadingNullCount = 0;
    mPages = List();
    mTrailingNullCount = 0;
    mPositionOffset = 0;
    mLoadedCount = 0;
    mStorageCount = 0;
    mPageSize = 1;
    mNumberPrepended = 0;
    mNumberAppended = 0;
  }

  PagedStorage.init(int leadingNulls, List<T> page, int trailingNulls) {
    init(leadingNulls, page, trailingNulls, 0);
  }

  void init(
      int leadingNulls, List<T> page, int trailingNulls, int positionOffset) {
    mLeadingNullCount = leadingNulls;
    mPages.clear();
    mPages.add(page);
    mTrailingNullCount = trailingNulls;

    mPositionOffset = positionOffset;
    mLoadedCount = page.length;
    mStorageCount = mLoadedCount;

    // initialized as tiled. There may be 3 nulls, 2 items, but we still call this tiled
    // even if it will break if nulls convert.
    mPageSize = page.length;

    mNumberPrepended = 0;
    mNumberAppended = 0;
  }

  PagedStorage.other(PagedStorage<T> other) {
    mLeadingNullCount = other.mLeadingNullCount;
    mPages = List()..addAll(other.mPages);
    mTrailingNullCount = other.mTrailingNullCount;
    mPositionOffset = other.mPositionOffset;
    mLoadedCount = other.mLoadedCount;
    mStorageCount = other.mStorageCount;
    mPageSize = other.mPageSize;
    mNumberPrepended = other.mNumberPrepended;
    mNumberAppended = other.mNumberAppended;
  }

  PagedStorage<T> snapshot() {
    return  PagedStorage.other(this);
  }

  void initWithCallback(int leadingNulls, List<T> page, int trailingNulls,
      int positionOffset, PagedStorageCallback callback) {
    init(leadingNulls, page, trailingNulls, positionOffset);
    callback.onInitialized(size());
  }

  T get(int i) {
    if (i < 0 || i >= size()) {
      throw new IndexError(i, "Index: $i, Size: $size()");
    }

    // is it definitely outside 'mPages'?
    int localIndex = i - mLeadingNullCount;
    if (localIndex < 0 || localIndex >= mStorageCount) {
      return null;
    }

    int localPageIndex;
    int pageInternalIndex;

    if (isTiled()) {
      // it's inside mPages, and we're tiled. Jump to correct tile.
      localPageIndex = localIndex ~/ mPageSize;
      pageInternalIndex = localIndex % mPageSize;
    } else {
      // it's inside mPages, but page sizes aren't regular. Walk to correct tile.
      // Pages can only be null while tiled, so accessing page count is safe.
      pageInternalIndex = localIndex;
      final int localPageCount = mPages.length;
      for (localPageIndex = 0;
          localPageIndex < localPageCount;
          localPageIndex++) {
        int pageSize = mPages[localPageIndex].length;
        if (pageSize > pageInternalIndex) {
          // stop, found the page
          break;
        }
        pageInternalIndex -= pageSize;
      }
    }

    List<T> page = mPages[localPageIndex];
    if (page == null || page.length == 0) {
      // can only occur in tiled case, with untouched inner/placeholder pages
      return null;
    }
    return page[pageInternalIndex];
  }

  int size() {
    return mLeadingNullCount + mStorageCount + mTrailingNullCount;
  }

  bool isEmpty(){
    return size() == 0;
  }

  /// Returns true if all pages are the same size, except for the last, which may be smaller
  bool isTiled() {
    return mPageSize > 0;
  }

  int getLeadingNullCount() {
    return mLeadingNullCount;
  }

  int getTrailingNullCount() {
    return mTrailingNullCount;
  }

  int getStorageCount() {
    return mStorageCount;
  }

  int getNumberAppended() {
    return mNumberAppended;
  }

  int getNumberPrepended() {
    return mNumberPrepended;
  }

  int getPageCount() {
    return mPages.length;
  }

  int getLoadedCount() {
    return mLoadedCount;
  }

  int getPositionOffset() {
    return mPositionOffset;
  }

  int getMiddleOfLoadedRange() {
    return mLeadingNullCount + mPositionOffset + mStorageCount ~/ 2;
  }

  int computeLeadingNulls() {
    int total = mLeadingNullCount;
    final int pageCount = mPages.length;
    for (int i = 0; i < pageCount; i++) {
      List page = mPages[i];
      if (page != null && page != PLACEHOLDER_LIST) {
        break;
      }
      total += mPageSize;
    }
    return total;
  }

  int computeTrailingNulls() {
    int total = mTrailingNullCount;
    for (int i = mPages.length - 1; i >= 0; i--) {
      List page = mPages[i];
      if (page != null && page != PLACEHOLDER_LIST) {
        break;
      }
      total += mPageSize;
    }
    return total;
  }

  // ---------------- Trimming API -------------------
  // Trimming is always done at the beginning or end of the list, as content is loaded.
  // In addition to trimming pages in the storage, we also support pre-trimming pages (dropping
  // them just before they're added) to avoid dispatching an add followed immediately by a trim.
  //
  // Note - we avoid trimming down to a single page to reduce chances of dropping page in
  // viewport, since we don't strictly know the viewport. If trim is aggressively set to size of a
  // single page, trimming while the user can see a page boundary is dangerous. To be safe, we
  // just avoid trimming in these cases entirely.

  bool _needsTrim(int maxSize, int requiredRemaining, int localPageIndex) {
    List<T> page = mPages[localPageIndex];
    return page == null ||
        (mLoadedCount > maxSize &&
            mPages.length > 2 &&
            page != PLACEHOLDER_LIST &&
            mLoadedCount - page.length >= requiredRemaining);
  }

  bool needsTrimFromFront(int maxSize, int requiredRemaining) {
    return _needsTrim(maxSize, requiredRemaining, 0);
  }

  bool needsTrimFromEnd(int maxSize, int requiredRemaining) {
    return _needsTrim(maxSize, requiredRemaining, mPages.length - 1);
  }

  bool shouldPreTrimNewPage(
      int maxSize, int requiredRemaining, int countToBeAdded) {
    return mLoadedCount + countToBeAdded > maxSize &&
        mPages.length > 1 &&
        mLoadedCount >= requiredRemaining;
  }

  bool trimFromFront(
      bool insertNulls, int maxSize, int requiredRemaining, PagedStorageCallback callback) {
    int totalRemoved = 0;
    while (needsTrimFromFront(maxSize, requiredRemaining)) {
      List page = mPages.removeAt(0);
      int removed = (page == null) ? mPageSize : page.length;
      totalRemoved += removed;
      mStorageCount -= removed;
      mLoadedCount -= (page == null) ? 0 : page.length;
    }

    if (totalRemoved > 0) {
      if (insertNulls) {
        // replace removed items with nulls
        int previousLeadingNulls = mLeadingNullCount;
        mLeadingNullCount += totalRemoved;
        callback.onPagesSwappedToPlaceholder(
            previousLeadingNulls, totalRemoved);
      } else {
        // simply remove, and handle offset
        mPositionOffset += totalRemoved;
        callback.onPagesRemoved(mLeadingNullCount, totalRemoved);
      }
    }
    return totalRemoved > 0;
  }

  bool trimFromEnd(
      bool insertNulls, int maxSize, int requiredRemaining, PagedStorageCallback callback) {
    int totalRemoved = 0;
    while (needsTrimFromEnd(maxSize, requiredRemaining)) {
      List page = mPages.removeAt(mPages.length - 1);
      int removed = (page == null) ? mPageSize : page.length;
      totalRemoved += removed;
      mStorageCount -= removed;
      mLoadedCount -= (page == null) ? 0 : page.length;
    }

    if (totalRemoved > 0) {
      int newEndPosition = mLeadingNullCount + mStorageCount;
      if (insertNulls) {
        // replace removed items with nulls
        mTrailingNullCount += totalRemoved;
        callback.onPagesSwappedToPlaceholder(newEndPosition, totalRemoved);
      } else {
        // items were just removed, signal
        callback.onPagesRemoved(newEndPosition, totalRemoved);
      }
    }
    return totalRemoved > 0;
  }

  // ---------------- Contiguous API -------------------

  T getFirstLoadedItem() {
    // safe to access first page's first item here:
    // If contiguous, mPages can't be empty, can't hold null Pages, and items can't be empty
    return mPages[0][0];
  }

  T getLastLoadedItem() {
    // safe to access last page's last item here:
    // If contiguous, mPages can't be empty, can't hold null Pages, and items can't be empty
    List<T> page = mPages[mPages.length - 1];
    return page[page.length - 1];
  }

  void prependPage(List<T> page, PagedStorageCallback callback) {
    final int count = page.length;
    if (count == 0) {
      // Nothing returned from source, stop loading in this direction
      callback.onEmptyPrepend();
      return;
    }
    if (mPageSize > 0 && count != mPageSize) {
      if (mPages.length == 1 && count > mPageSize) {
        // prepending to a single item - update current page size to that of 'inner' page
        mPageSize = count;
      } else {
        // no longer tiled
        mPageSize = -1;
      }
    }

    mPages.insert(0, page);
    mLoadedCount += count;
    mStorageCount += count;

    final int changedCount =
        mLeadingNullCount < count ? mLeadingNullCount : count;
    final int addedCount = count - changedCount;

    if (changedCount != 0) {
      mLeadingNullCount -= changedCount;
    }
    mPositionOffset -= addedCount;
    mNumberPrepended += count;

    callback.onPagePrepended(mLeadingNullCount, changedCount, addedCount);
  }

  void appendPage(List<T> page, PagedStorageCallback callback) {
    final int count = page.length;
    if (count == 0) {
      // Nothing returned from source, stop loading in this direction
      callback.onEmptyAppend();
      return;
    }

    if (mPageSize > 0) {
      // if the previous page was smaller than mPageSize,
      // or if this page is larger than the previous, disable tiling
      if (mPages[mPages.length - 1].length != mPageSize || count > mPageSize) {
        mPageSize = -1;
      }
    }

    mPages.add(page);
    mLoadedCount += count;
    mStorageCount += count;

    final int changedCount =
        mLeadingNullCount < count ? mLeadingNullCount : count;
    final int addedCount = count - changedCount;

    if (changedCount != 0) {
      mTrailingNullCount -= changedCount;
    }
    mNumberAppended += count;
    callback.onPageAppended(
        mLeadingNullCount + mStorageCount - count, changedCount, addedCount);
  }

  // ------------------ Non-Contiguous API (tiling required) ----------------------

  /// Return true if the page at the passed position would be the first (if trimFromFront) or last
  /// page that's currently loading.
  bool pageWouldBeBoundary(int positionOfPage, bool trimFromFront) {
    if (mPageSize < 1 || mPages.length < 2) {
      throw new Exception("Trimming attempt before sufficient load");
    }

    if (positionOfPage < mLeadingNullCount) {
      // position represent page in leading nulls
      return trimFromFront;
    }

    if (positionOfPage >= mLeadingNullCount + mStorageCount) {
      // position represent page in trailing nulls
      return !trimFromFront;
    }

    int localPageIndex =
        (positionOfPage - mLeadingNullCount) ~/ mPageSize;

    // walk outside in, return false if we find non-placeholder page before localPageIndex
    if (trimFromFront) {
      for (int i = 0; i < localPageIndex; i++) {
        if (mPages[i] != null) {
          return false;
        }
      }
    } else {
      for (int i = mPages.length - 1; i > localPageIndex; i--) {
        if (mPages[i] != null) {
          return false;
        }
      }
    }

    // didn't find another page, so this one would be a boundary
    return true;
  }

  void initAndSplit(int leadingNulls, List<T> multiPageList, int trailingNulls,
      int positionOffset, int pageSize, PagedStorageCallback callback) {
    int pageCount = (multiPageList.length + (pageSize - 1)) ~/ pageSize;
    for (int i = 0; i < pageCount; i++) {
      int beginInclusive = i * pageSize;
      int endExclusive = min(multiPageList.length, (i + 1) * pageSize);

      List<T> sublist = multiPageList.sublist(beginInclusive, endExclusive);

      if (i == 0) {
        // Trailing nulls for first page includes other pages in multiPageList
        int initialTrailingNulls =
            trailingNulls + multiPageList.length - sublist.length;
        init(leadingNulls, sublist, initialTrailingNulls, positionOffset);
      } else {
        int insertPosition = leadingNulls + beginInclusive;
        insertPage(insertPosition, sublist, null);
      }
    }
    callback.onInitialized(size());
  }

  void tryInsertPageAndTrim(int position, List<T> page, int lastLoad,
      int maxSize, int requiredRemaining, PagedStorageCallback callback) {
    bool trim = maxSize != Config.MAX_SIZE_UNBOUNDED;
    bool mTrimFromFront = lastLoad > getMiddleOfLoadedRange();

    bool pageInserted = !trim ||
        !shouldPreTrimNewPage(maxSize, requiredRemaining, page.length) ||
        !pageWouldBeBoundary(position, mTrimFromFront);

    if (pageInserted) {
      insertPage(position, page, callback);
    } else {
      // trim would have us drop the page we just loaded - swap it to null
      int localPageIndex = (position - mLeadingNullCount) ~/ mPageSize;
      mPages[localPageIndex] = null;

      // note: we also remove it, so we don't have to guess how large a 'null' page is later
      mStorageCount -= page.length;
      if (mTrimFromFront) {
        mPages.remove(0);
        mLeadingNullCount += page.length;
      } else {
        mPages.remove(mPages.length - 1);
        mTrailingNullCount += page.length;
      }
    }

    if (trim) {
      if (mTrimFromFront) {
        trimFromFront(true, maxSize, requiredRemaining, callback);
      } else {
        trimFromEnd(true, maxSize, requiredRemaining, callback);
      }
    }
  }

  void insertPage(int position, List<T> page, PagedStorageCallback callback) {
    final int newPageSize = page.length;
    if (newPageSize != mPageSize) {
      // differing page size is OK in 2 cases, when the page is being added:
      // 1) to the end (in which case, ignore new smaller size)
      // 2) only the last page has been added so far (in which case, adopt new bigger size)

      int mSize = size();
      bool addingLastPage =
          position == (mSize - mSize % mPageSize) && newPageSize < mPageSize;
      bool onlyEndPagePresent = mTrailingNullCount == 0 &&
          mPages.length == 1 &&
          newPageSize > mPageSize;

      // OK only if existing single page, and it's the last one
      if (!onlyEndPagePresent && !addingLastPage) {
        throw new Exception("page introduces incorrect tiling");
      }
      if (onlyEndPagePresent) {
        mPageSize = newPageSize;
      }
    }

    int pageIndex = position ~/ mPageSize;

    allocatePageRange(pageIndex, pageIndex);

    int localPageIndex = (pageIndex - mLeadingNullCount / mPageSize).toInt();

    List<T> oldPage = mPages[localPageIndex];
    if (oldPage != null && oldPage != PLACEHOLDER_LIST) {
      throw new Exception("Invalid position $position : data already loaded");
    }
    mPages[localPageIndex] = page;
    mLoadedCount += newPageSize;
    if (callback != null) {
      callback.onPageInserted(position, newPageSize);
    }
  }

  void allocatePageRange(final int minimumPage, final int maximumPage) {
    int leadingNullPages = mLeadingNullCount ~/ mPageSize;

    if (minimumPage < leadingNullPages) {
      for (int i = 0; i < leadingNullPages - minimumPage; i++) {
        mPages.insert(0, null);
      }
      int newStorageAllocated = (leadingNullPages - minimumPage) * mPageSize;
      mStorageCount += newStorageAllocated;
      mLeadingNullCount -= newStorageAllocated;

      leadingNullPages = minimumPage;
    }
    if (maximumPage >= leadingNullPages + mPages.length) {
      int newStorageAllocated = min(mTrailingNullCount,
          (maximumPage + 1 - (leadingNullPages + mPages.length)) * mPageSize);
      for (int i = mPages.length; i <= maximumPage - leadingNullPages; i++) {
        mPages.insert(mPages.length, null);
      }
      mStorageCount += newStorageAllocated;
      mTrailingNullCount -= newStorageAllocated;
    }
  }

  void allocatePlaceholders(
      int index, int prefetchDistance, int pageSize, PagedStorageCallback callback) {
    if (pageSize != mPageSize) {
      if (pageSize < mPageSize) {
        throw new Exception("Page size cannot be reduced");
      }
      if (mPages.length != 1 || mTrailingNullCount != 0) {
        // not in single, last page allocated case - can't change page size
        throw new Exception(
            "Page size can change only if last page is only one present");
      }
      mPageSize = pageSize;
    }

    final int maxPageCount = (size() + mPageSize - 1) ~/ mPageSize;
    int minimumPage = max((index - prefetchDistance) ~/ mPageSize, 0);
    int maximumPage =
        min((index + prefetchDistance) ~/ mPageSize, maxPageCount - 1);

    allocatePageRange(minimumPage, maximumPage);
    int leadingNullPages = mLeadingNullCount ~/ mPageSize;
    for (int pageIndex = minimumPage; pageIndex <= maximumPage; pageIndex++) {
      int localPageIndex = pageIndex - leadingNullPages;
      if (mPages[localPageIndex] == null) {
        //noinspection unchecked
        mPages[localPageIndex] = PLACEHOLDER_LIST;
        callback.onPagePlaceholderInserted(pageIndex);
      }
    }
  }

  bool hasPage(int pageSize, int index) {
    // NOTE: we pass pageSize here to avoid in case mPageSize
    // not fully initialized (when last page only one loaded)
    int leadingNullPages = mLeadingNullCount ~/ pageSize;

    if (index < leadingNullPages || index >= leadingNullPages + mPages.length) {
      return false;
    }

    List<T> page = mPages[index - leadingNullPages];

    return page != null && page != PLACEHOLDER_LIST;
  }

  @override
  String toString() {
    String ret =
        "leading $mLeadingNullCount , storage $mStorageCount, trailing  ${getTrailingNullCount()}";

    for (int i = 0; i < mPages.length; i++) {
      ret = ret + " " + mPages[i].toString();
    }
    return ret;
  }
}

abstract class PagedStorageCallback {
  void onInitialized(int count);

  void onPagePrepended(int leadingNulls, int changed, int added);

  void onPageAppended(int endPosition, int changed, int added);

  void onPagePlaceholderInserted(int pageIndex);

  void onPageInserted(int start, int count);

  void onPagesRemoved(int startOfDrops, int count);

  void onPagesSwappedToPlaceholder(int startOfDrops, int count);

  void onEmptyPrepend();

  void onEmptyAppend();
}
