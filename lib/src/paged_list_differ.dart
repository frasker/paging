import 'dart:math';

import 'page_list.dart';

class AsyncPagedListDiffer<T> {
  bool mIsContiguous;

  PagedList<T> mPagedList;
  PagedList<T> mSnapshot;

  final List<PagedListListener<T>> mListeners = List();

  T getItem(int index) {
    if (mPagedList == null) {
      if (mSnapshot == null) {
        throw new IndexError(
            index, "Item count is zero, getItem() call is invalid");
      } else {
        return mSnapshot.get(index);
      }
    }

    mPagedList.loadAround(index);
    return mPagedList.get(index);
  }

  int getItemCount() {
    if (mPagedList != null) {
      return mPagedList.size();
    }

    return mSnapshot == null ? 0 : mSnapshot.size();
  }

  void submitList(final PagedList<T> pagedList, {Function commitCallback}) {
    if (pagedList != null) {
      if (mPagedList == null && mSnapshot == null) {
        mIsContiguous = pagedList.isContiguous();
      } else {
        if (pagedList.isContiguous() != mIsContiguous) {
          throw new Exception("PagedListDiffer cannot handle both" +
              " contiguous and non-contiguous lists.");
        }
      }
    }

    if (pagedList == mPagedList) {
      // nothing to do (Note - still had to inc generation, since may have ongoing work)
      if (commitCallback != null) {
        commitCallback();
      }
      return;
    }

    final PagedList<T> previous = (mSnapshot != null) ? mSnapshot : mPagedList;
    if (pagedList == null) {
      if (mPagedList != null) {
        mPagedList = null;
      } else if (mSnapshot != null) {
        mSnapshot = null;
      }
      onCurrentListChanged(previous, null, commitCallback);
      return;
    }

    if (mPagedList == null && mSnapshot == null) {
      // fast simple first insert
      mPagedList = pagedList;
      onCurrentListChanged(null, pagedList, commitCallback);
      return;
    }

    mPagedList = null;

    if (mSnapshot == null || mPagedList != null) {
      throw new Exception("must be in snapshot state to diff");
    }

    final PagedList<T> oldSnapshot = mSnapshot;
    final PagedList<T> newSnapshot = pagedList.snapshot();

    latchPagedList(
        pagedList, newSnapshot, oldSnapshot.mLastLoad, commitCallback);
  }

  void onCurrentListChanged(PagedList<T> previousList, PagedList<T> currentList,
      Function commitCallback) {
    for (PagedListListener<T> listener in mListeners) {
      listener.onCurrentListChanged(previousList, currentList);
    }
    if (commitCallback != null) {
      commitCallback();
    }
  }

  void latchPagedList(PagedList<T> newList, PagedList<T> diffSnapshot,
      int lastAccessIndex, Function commitCallback) {
    if (mSnapshot == null || mPagedList != null) {
      throw new Exception("must be in snapshot state to apply diff");
    }
    PagedList<T> previousSnapshot = mSnapshot;
    mPagedList = newList;
    mSnapshot = null;
    if (!mPagedList.isEmpty()) {
      // Transform the last loadAround() index from the old list to the new list by passing it
      // through the DiffResult. This ensures the lastKey of a positional PagedList is carried
      // to new list even if no in-viewport item changes (AsyncPagedListDiffer#get not called)
      // Note: we don't take into account loads between new list snapshot and new list, but
      // this is only a problem in rare cases when placeholders are disabled, and a load
      // starts (for some reason) and finishes before diff completes.

      // not anchored to an item in new list, so just reuse position (clamped to newList size)
      int newPosition = max(0, min(lastAccessIndex, newList.size() - 1));
      // Trigger load in new list at this position, clamped to list bounds.
      // This is a load, not just an update of last load position, since the new list may be
      // incomplete. If new list is subset of old list, but doesn't fill the viewport, this
      // will likely trigger a load of new data.
      mPagedList.loadAround(max(0, min(mPagedList.size() - 1, newPosition)));
    }

    onCurrentListChanged(previousSnapshot, mPagedList, commitCallback);
  }

  /// Add a PagedListListener to receive updates when the current PagedList changes.
  ///
  /// @param listener Listener to receive updates.
  ///
  /// @see #getCurrentList()
  /// @see #removePagedListListener(PagedListListener)
  void addPagedListListener(PagedListListener<T> listener) {
    mListeners.add(listener);
  }

  /// Remove a previously registered PagedListListener.
  ///
  /// @param listener Previously registered listener.
  /// @see #getCurrentList()
  /// @see #addPagedListListener(PagedListListener)
  void removePagedListListener(PagedListListener<T> listener) {
    mListeners.remove(listener);
  }

  /// Returns the PagedList currently being displayed by the differ.
  /// <p>
  /// This is not necessarily the most recent list passed to {@link #submitList(PagedList)},
  /// because a diff is computed asynchronously between the new list and the current list before
  /// updating the currentList value. May be null if no PagedList is being presented.
  ///
  /// @return The list currently being displayed, may be null.
  PagedList<T> getCurrentList() {
    if (mSnapshot != null) {
      return mSnapshot;
    }
    return mPagedList;
  }
}

/// Listener for when the current PagedList is updated.
///
/// @param <T> Type of items in PagedList
abstract class PagedListListener<T> {
  /// Called after the current PagedList has been updated.
  ///
  /// @param previousList The previous list, may be null.
  /// @param currentList The new current list, may be null.
  void onCurrentListChanged(
      PagedList<T> previousList, PagedList<T> currentList);
}
