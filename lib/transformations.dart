import 'package:paging/observable_field.dart';

/// Called when the data is changed.
/// @param t  The new data
typedef Observer<T> = Function(T t);

class Transformations {
  /// Returns a {@code ObservableField} mapped from the input {@code source} {@code ObservableField} by applying
  /// {@code mapFunction} to each value set on {@code source}.
  /// <p>
  /// This method is analogous to {@link io.reactivex.Observable#map}.
  /// <p>
  /// {@code transform} will be executed on the main thread.
  /// <p>
  /// Here is an example mapping a simple {@code User} struct in a {@code ObservableField} to a
  /// {@code ObservableField} containing their full name as a {@code String}.
  ///
  /// <pre>
  /// ObservableField<User> userObservableField = ...;
  /// ObservableField<String> userFullNameLiveData =
  ///     Transformations.map(
  ///         userObservableField,
  ///         user -> user.firstName + user.lastName);
  /// });
  /// </pre>
  ///
  /// @param source      the {@code ObservableField} to map from
  /// @param mapFunction a function to apply to each value set on {@code source} in order to set
  ///                    it
  ///                    on the output {@code ObservableField}
  /// @param <X>         the generic type parameter of {@code source}
  /// @param <Y>         the generic type parameter of the returned {@code ObservableField}
  /// @return a ObservableField mapped from {@code source} to type {@code <Y>} by applying
  /// {@code mapFunction} to each value set.
  static ObservableField<Y> map<X, Y>(
      ObservableField<X> source, Y mapFunction(X x)) {
    final MediatorObservableField<Y> result = new MediatorObservableField<Y>();
    result.addSource(source, (x) {
      result.value = mapFunction(x);
    });
    return result;
  }

  /// Returns a {@code ObservableField} mapped from the input {@code source} {@code ObservableField} by applying
  /// {@code switchMapFunction} to each value set on {@code source}.
  /// <p>
  /// The returned {@code ObservableField} delegates to the most recent {@code ObservableField} created by
  /// calling {@code switchMapFunction} with the most recent value set to {@code source}, without
  /// changing the reference. In this way, {@code switchMapFunction} can change the 'backing'
  /// {@code ObservableField} transparently to any observer registered to the {@code ObservableField} returned
  /// by {@code switchMap()}.
  /// <p>
  /// Note that when the backing {@code ObservableField} is switched, no further values from the older
  /// {@code ObservableField} will be set to the output {@code ObservableField}. In this way, the method is
  /// analogous to {@link io.reactivex.Observable#switchMap}.
  ///
  /// Here is an example class that holds a typed-in name of a user
  /// {@code String} (such as from an {@code EditText}) in a {@link ObservableField} and
  /// returns a {@code ObservableField} containing a List of {@code User} objects for users that have
  /// that name. It populates that {@code ObservableField} by requerying a repository-pattern object
  /// each time the typed name changes.
  /// <p>
  /// This {@code ViewModel} would permit the observing UI to update "live" as the user ID text
  /// changes.
  ///
  /// <pre>
  /// class UserViewModel extends ViewModel {
  ///     MutableLiveData<String> nameQueryLiveData = ...
  ///
  ///     ObservableField<List<String>> getUsersWithNameObservableField() {
  ///         return Transformations.switchMap(
  ///             nameQueryObservableField,
  ///                 name -> myDataSource.getUsersWithNameObservableField(name));
  ///     }
  ///
  ///     void setNameQuery(String name) {
  ///         this.nameQueryObservableField.setValue(name);
  ///     }
  /// }
  /// </pre>
  ///
  /// @param source            the {@code ObservableField} to map from
  /// @param switchMapFunction a function to apply to each value set on {@code source} to create a
  ///                          new delegate {@code ObservableField} for the returned one
  /// @param <X>               the generic type parameter of {@code source}
  /// @param <Y>               the generic type parameter of the returned {@code LiveData}
  /// @return a ObservableField mapped from {@code source} to type {@code <Y>} by delegating
  /// to the ObservableField returned by applying {@code switchMapFunction} to each
  /// value set
  static ObservableField<Y> switchMap<X, Y>(ObservableField<X> source,
      ObservableField<Y> switchMapFunction(X source)) {
    final MediatorObservableField<Y> result = new MediatorObservableField<Y>();
    ObservableField<Y> mSource;
    result.addSource(source, (x) {
      ObservableField<Y> newLiveData = switchMapFunction(x);
      if (mSource == newLiveData) {
        return;
      }
      if (mSource != null) {
        result.removeSource(mSource);
      }
      mSource = newLiveData;
      if (mSource != null) {
        result.addSource(mSource, (y) {
          result.value = y;
        });
      }
    });
    return result;
  }
}

class MediatorObservableField<T> extends ObservableField<T> {
  Map<ObservableField, Source> mSources = new Map();

  void addSource<S>(ObservableField<S> source, Observer<S> onChanged) {
    Source<S> e = new Source<S>(source, onChanged);
    Source existing = mSources[source];
    if (existing != null && existing.mObserver != onChanged) {
      throw new Exception(
          "This source was already added with the different observer");
    }
    if (existing != null) {
      return;
    }

    mSources.putIfAbsent(source, () {
      return e;
    });

    e.plug();
  }

  void removeSource<S>(ObservableField<S> toRemote) {
    Source source = mSources.remove(toRemote);
    if (source != null) {
      source.unplug();
    }
  }
}

class Source<V> {
  final ObservableField<V> mObservableFieldData;
  final Observer<V> mObserver;
  int mVersion = ObservableField.START_VERSION;

  void _onListen() {
    onChanged(mObservableFieldData.value);
  }

  Source(this.mObservableFieldData, this.mObserver);

  void plug() {
    mObservableFieldData.addListener(_onListen);
  }

  void unplug() {
    mObservableFieldData.removeListener(_onListen);
  }

  void onChanged(V v) {
    if (mVersion != mObservableFieldData.version) {
      mVersion = mObservableFieldData.version;
      mObserver(v);
    }
  }
}
