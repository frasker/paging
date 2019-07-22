import 'observable_field.dart';
import 'src/data_source.dart';
import 'src/page_list.dart';

class PagedListBuilder<Key, Value> {
  final Key mInitialLoadKey;
  final Config mConfig;
  final Factory<Key, Value> mDataSourceFactory;
  final BoundaryCallback mBoundaryCallback;

  PagedListBuilder(this.mConfig, this.mDataSourceFactory,
      {this.mInitialLoadKey, this.mBoundaryCallback});

  PagedList<Value> mList;
  DataSource<Key, Value> mDataSource;
  ObservableField<PagedList<Value>> _data = ObservableField();

  void invalidatedCallback() {
    _data.value = _get();
  }

  PagedList<Value> _get() {
    Key initializeKey = mInitialLoadKey;
    if (mList != null) {
      initializeKey = mList.getLastKey();
    }
    do {
      if (mDataSource != null) {
        mDataSource.removeInvalidatedCallback(invalidatedCallback);
      }
      mDataSource = mDataSourceFactory.create();
      mDataSource.addInvalidatedCallback(invalidatedCallback);

      mList = PagedList.create<Key, Value>(
          mDataSource, mBoundaryCallback, mConfig, initializeKey);
    } while (mList.isDetached());
    return mList;
  }

  ObservableField<PagedList<Value>> create() {
    _data.value = _get();
    return _data;
  }
}
