import 'package:livedata/livedata.dart';

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
  MutableLiveData<PagedList<Value>> _data = MutableLiveData();

  void invalidatedCallback() async{
    _data.value = await _get();
  }

  Future<PagedList<Value>> _get() async {
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

  LiveData<PagedList<Value>> create() {
    _get().then((value) {
      _data.value = value;
    });
    return _data;
  }
}
