import 'package:flutter/widgets.dart';
import 'package:paging/observable_field.dart';
import 'package:paging/src/page_list.dart';
import 'package:paging/src/paged_list_differ.dart';

import 'listupdate_callback.dart';

class PageBuilder<T> extends StatefulWidget {
  PageBuilder(
      {Key key,
      @required this.pageListLiveData,
      @required this.builder,
      this.child,
      this.pagedListListener})
      : assert(builder != null),
        super(key: key);

  final Widget child;

  /// Must not be null.
  final Widget Function(BuildContext context,
      PagedListDiffer<T> pagedListDiffer, Widget child) builder;

  final PagedListListener<T> pagedListListener;

  final ObservableField<PagedList<T>> pageListLiveData;

  @override
  _PageBuilderState createState() =>
      _PageBuilderState<T>(builder, pagedListListener);
}

class _PageBuilderState<T> extends State<PageBuilder> with ListUpdateCallback {
  /// Must not be null.
  final Widget Function(BuildContext context,
      PagedListDiffer<T> pagedListDiffer, Widget child) builder;

  final PagedListListener<T> pagedListListener;

  PagedListDiffer<T> pagedListDiffer;

  PagedList<T> previousList;

  PagedList<T> currentList;

  _PageBuilderState(this.builder, this.pagedListListener);

  void _pageListChanged() {
    pagedListDiffer.submitList(widget.pageListLiveData.value);
  }

  @override
  void initState() {
    pagedListDiffer = PagedListDiffer<T>(this);
    if (pagedListListener != null) {
      pagedListDiffer.addPagedListListener(pagedListListener);
    }
    widget.pageListLiveData.addListener(_pageListChanged);
    super.initState();
  }

  @override
  void dispose() {
    pagedListDiffer.dispose();
    if (pagedListListener != null) {
      pagedListDiffer.removePagedListListener(pagedListListener);
    }
    widget.pageListLiveData.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return builder(
      context,
      pagedListDiffer,
      widget.child,
    );
  }

  @override
  void onChanged() {
    setState(() {});
  }
}
