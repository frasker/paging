import 'package:flutter/material.dart';
import 'package:paging/paging.dart';
import 'package:paging/widget/page_builder.dart';

import 'bean.dart';
import 'test_paging.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  ValueNotifier<PagedList<Bean>> mPageList;

  var _scrollController = ScrollController();

  @override
  void initState() {
    MyFactory factory = MyFactory();
    var config =
        Config(pageSize: 5, enablePlaceholders: false, initialLoadSizeHint: 10);
    mPageList =
        LivePagedListBuilder<int, Bean>(config, factory).create();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
        appBar: AppBar(
          // Here we take the value from the MyHomePage object that was created by
          // the App.build method, and use it to set our appbar title.
          title: Text(widget.title),
        ),
        body: Center(
          // Center is a layout widget. It takes a single child and positions it
          // in the middle of the parent.
          child: PageBuilder<Bean>(
            pageList: mPageList,
            builder: (context, pagedListDiffer, child) {
              return ListView.separated(
                  physics: AlwaysScrollableScrollPhysics(),
                  controller: _scrollController,
                  itemBuilder: (context, position) {
                    var bean = pagedListDiffer.getItem(position);
                    print(
                        "当前位置$position  count ${pagedListDiffer.getItemCount()} ${bean?.toString()}");

                    return Text(
                      "text  $position",
                    );
                  },
                  separatorBuilder: (context, position) {
                    return Divider();
                  },
                  itemCount: pagedListDiffer.getItemCount());
            },
            pagedListListener: (preList, curList) {
              print(preList?.toString() ??
                  "null" + ",   " + curList?.toString() ??
                  "null");
            },
          ),
        ));
  }
}
