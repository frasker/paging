import 'data_source.dart';
import 'page_result.dart';

abstract class ContiguousDataSource<Key, Value> extends DataSource<Key, Value> {
  @override
  bool isContiguous() {
    return true;
  }

  void dispatchLoadInitial(Key key, int initialLoadSize, int pageSize,
      bool enablePlaceholders, PageResultReceiver<Value> receiver);

  void dispatchLoadAfter(int currentEndIndex, Value currentEndItem,
      int pageSize, PageResultReceiver<Value> receiver);

  void dispatchLoadBefore(int currentBeginIndex, Value currentBeginItem,
      int pageSize, PageResultReceiver<Value> receiver);

  /// Get the key from either the position, or item, or null if position/item invalid.
  /// <p>
  /// Position may not match passed item's position - if trying to query the key from a position
  /// that isn't yet loaded, a fallback item (last loaded item accessed) will be passed.
  Key getKey(int position, Value item);

  bool supportsPageDropping() {
    return true;
  }
}
