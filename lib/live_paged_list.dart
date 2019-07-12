import 'livedata.dart';
import 'mutable_livedata.dart';
import 'src/contiguous_paged_list.dart';
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
  MutableLiveData<PagedList<Value>> _liveData = MutableLiveData();

  void invalidatedCallback() {
    _liveData.value = _get();
  }

  PagedList<Value> _get() {
    Key initializeKey = mInitialLoadKey;
    if (mList != null) {
      initializeKey = mList.getLastKey();
    }
    if (mDataSource != null) {
      mDataSource.removeInvalidatedCallback(invalidatedCallback);
    }
    mDataSource = mDataSourceFactory.create();
    mDataSource.addInvalidatedCallback(invalidatedCallback);
    mList = ContiguousPagedList(mDataSource, mBoundaryCallback, mConfig,
        initializeKey, ContiguousPagedList.LAST_LOAD_UNSPECIFIED);
    return mList;
  }

  LiveData<PagedList<Value>> create() {
    _liveData.value = _get();
    return _liveData;
  }
}
