import 'dart:async';

import 'package:flutter/widgets.dart';
import 'src/data_source.dart';
import 'src/page_list.dart';

class LivePagedListBuilder<Key, Value> {
  final Key mInitialLoadKey;
  final Config mConfig;
  final Factory<Key, Value> mDataSourceFactory;
  final BoundaryCallback mBoundaryCallback;

  LivePagedListBuilder(this.mConfig, this.mDataSourceFactory,
      {this.mInitialLoadKey, this.mBoundaryCallback});

  PagedList<Value> mList;
  DataSource<Key, Value> mDataSource;
  ValueNotifier<PagedList<Value>> _data = ValueNotifier(null);

  void _invalidatedCallback(Completer<void> completer) {
    _get(completer).then((data) {
      _data.value = data;
    });
  }

  Future<PagedList<Value>> _get(Completer<void> completer) {
    final Completer<PagedList<Value>> _completer = Completer<PagedList<Value>>();
    Key initializeKey = mInitialLoadKey;
    if (mList != null) {
      initializeKey = mList.getLastKey();
    }

    if (mDataSource != null) {
      mDataSource.removeInvalidatedCallback();
    }
    mDataSource = mDataSourceFactory.create();
    mDataSource.addInvalidatedCallback(_invalidatedCallback);

    mList = PagedList.create<Key, Value>(
        mDataSource, mBoundaryCallback, mConfig, initializeKey, completer);
    completer.future.then((result){
      _completer.complete(mList);
    },onError: (e){
      _completer.completeError(e);
    });
    return _completer.future;
  }

  ValueNotifier<PagedList<Value>> create() {
    _get(Completer<void>()).then((data) {
      _data.value = data;
    });
    return _data;
  }
}
