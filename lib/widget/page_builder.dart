import 'package:flutter/widgets.dart';
import 'package:paging/livedata.dart';
import 'package:paging/src/page_list.dart';
import 'package:paging/src/paged_list_differ.dart';

class PageBuilder<T> extends StatefulWidget {
  PageBuilder({
    Key key,
    @required this.pageListLiveData,
    @required this.builder,
    this.child,
  })  : assert(builder != null),
        super(key: key);

  final Widget child;

  /// Must not be null.
  final Widget Function(BuildContext context, PagedList<T> previousList,
      PagedList<T> currentList, Widget child) builder;

  final LiveData<PagedList<T>> pageListLiveData;

  @override
  _PageBuilderState createState() => _PageBuilderState();
}

class _PageBuilderState<T> extends State<PageBuilder>
    with PagedListListener<T> {
  AsyncPagedListDiffer<T> pagedListDiffer;

  PagedList<T> previousList;

  PagedList<T> currentList;

  void _pageListChanged() {
    pagedListDiffer.submitList(widget.pageListLiveData.value);
  }

  @override
  void initState() {
    pagedListDiffer = AsyncPagedListDiffer();
    pagedListDiffer.addPagedListListener(this);
    widget.pageListLiveData.addListener(_pageListChanged);
    super.initState();
  }

  @override
  void dispose() {
    pagedListDiffer.removePagedListListener(this);
    widget.pageListLiveData.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      previousList,
      currentList,
      widget.child,
    );
  }

  @override
  void onCurrentListChanged(
      PagedList<T> previousList, PagedList<T> currentList) {
    setState(() {
      this.previousList = previousList;
      this.currentList = currentList;
    });
  }
}
