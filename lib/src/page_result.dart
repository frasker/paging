class PageResult<T> {
  /// Single empty instance to avoid allocations.
  /// <p>
  /// Note, distinct from {@link #INVALID_RESULT} because {@link #isInvalid()} checks instance.

  static final PageResult EMPTY_RESULT = PageResult(List(), 0);
  static final PageResult INVALID_RESULT = PageResult(List(), 0);

  static PageResult<T> getEmptyResult<T>() {
    return EMPTY_RESULT;
  }

  static PageResult<T> getInvalidResult<T>() {
    return INVALID_RESULT;
  }

  static final int INIT = 0;

  // contiguous results
  static final int APPEND = 1;
  static final int PREPEND = 2;

  // non-contiguous, tile result
  static final int TILE = 3;

  final List<T> page;

  final int leadingNulls;

  final int trailingNulls;

  final int positionOffset;

  PageResult(this.page, this.positionOffset,
      {this.leadingNulls = 0, this.trailingNulls = 0});

  @override
  String toString() {
    return "Result $leadingNulls , $page , $trailingNulls , offset $positionOffset";
  }

  bool isInvalid() {
    return this == INVALID_RESULT;
  }
}

abstract class PageResultReceiver<T> {
  void onPageResult(int type, PageResult<T> pageResult);
}
