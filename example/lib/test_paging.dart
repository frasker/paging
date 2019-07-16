import 'package:paging/paging.dart';

import 'bean.dart';

class MyFactory extends Factory<int, Bean> {
  @override
  DataSource<int, Bean> create() {
    return MyDataSource();
  }
}

class MyDataSource extends PageKeyedDataSource<int, Bean> {
  var mDataRepository = Bean();
  var pages = 0;

  @override
  void loadAfter(LoadParams<int> params, LoadCallback<int, Bean> callback) {
    if (params.key == 0) {
      callback.onResult(List<Bean>(), 0);
    } else {
      pages++;
      load(params.key).then((data) {
        callback.onResult(data, pages > 5 ? 0 : 1);
      });
    }
  }

  @override
  loadBefore(LoadParams<int> params, LoadCallback<int, Bean> callback) {
    // ignored, since we only ever append to our initial load
  }

  @override
  void loadInitial(
      LoadInitialParams<int> params, LoadInitialCallback<int, Bean> callback) {
    load(0).then((data) {
      callback.onResult(data, null, 1);
    });
  }

  Future<List<Bean>> load(int lastId) async {
    print("load data");
    return List.generate(5, (index) {
      return Bean();
    });
  }

  Future<List<Bean>> loadNulls(int lastId) async {
    print("load data");
    return List.generate(5, (index) {
      return null;
    });
  }
}
