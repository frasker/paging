# paging

paging 是针对flutter提供的分页加载库，思想和实现源自android jetpack 的架构组件Paging

## 如何使用

具体参见demo，和android paging不一样的地方在于针对flutter提供了PageBuilder控件
```
// 创建PageListLiveData
MyFactory factory = MyFactory();
var config = Config(pageSize: 5, enablePlaceholders: false, initialLoadSizeHint: 10);
mPageListLiveData = LivePagedListBuilder<int, Bean>(config, factory).create();

// 使用PageBuilder 包裹实现Listview
          child: PageBuilder<Bean>(
            pageListLiveData: mPageListLiveData,
            builder: (context, pagedListDiffer, child) {
              return ListView.separated(
                  physics: AlwaysScrollableScrollPhysics(),
                  controller: _scrollController,
                  itemBuilder: (context, position) {
                    var bean = pagedListDiffer.getItem(position);
                    return Text(
                      "当前位置$position  count ${pagedListDiffer.getItemCount()} ${bean?.toString()}"",
                    );
                  },
                  separatorBuilder: (context, position) {
                    return Divider();
                  },
                  itemCount: pagedListDiffer.getItemCount());
            },
          )
```
## 如何依赖
暂时请依赖github
```
 paging:
    git: https://github.com/frasker/paging
```

