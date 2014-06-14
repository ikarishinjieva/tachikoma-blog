+++
draft = false
title = "对mysql table cache的理解"
date = 2014-05-15T20:59:00Z
tags = [ "mysql", "table cache"]
+++

最近读了mysql table_cache部分的一些代码.

首先推荐这篇[导读](http://blog.sina.com.cn/s/blog_4673e60301010r5u.html), 写的比较详尽. 不对其中已有的部分进行重复, 仅记录自己的一些理解.

最简单的功能
---

叫做table_cache, 就是对`table`做擦车(cache). 

其中`table`是指的mysql打开的表的描述结构(descriptor)([`TABLE`](http://osxr.org/mysql/source/sql/table.h#0974)),  简单理解就是mysql要操作一张表时, 就会先打开其descriptor, 打开后读取其中信息, 然后进行操作.

为了快速访问, cache 往往类似于 Hash. table_cache 的 key 是
    db_name + table_name
table_cache 的 value 是 descriptor 的集合, 即 [`Table_cache_element`](http://osxr.org/mysql/source/sql/table_cache.h#0208). 

value 是 descriptor 的集合而不是 descriptor, 是因为对于同一张表, 在cache中同时会打开多个 descriptor

额外一提, table_cache是按线程号分桶的, 参看`Table_cache_manager`

进一步, 留下被回收的元素
---

传统擦车, 不用的元素就直接回收了. table_cache暂存了不用的元素, 提高命中率. 

可以看到`Table_cache_element`一共两个列表:

* used_tables
* free_tables

进一步, 抽出共同的部分
---

同一张表的多个 descriptor, 会有公共部分, 抽出这些公共部分, 能有效节省资源. 

比如`mem_root` (个人称之为受管内存区), 此内存区管理着跟某表相关的一些数据结构, 且受mysqld的管制. 如果同一张表的每个 descriptor 都独立管理一篇内存, 会引起不必要的浪费.

抽出的公共部分称为[`TABLE_SHARE`](http://osxr.org/mysql/source/sql/table.h#0584)

进一步, 公共部分也得擦车
---

`TABLE_SHARE` 也被擦车了, 其被回收的元素跟`TABLE`一样也被擦车了.

擦车的步骤
---

简述擦车的步骤

1. 在cache中查找`TABLE`
2. 如果找到`TABLE`, 则成功
3. 在cache中查找`TABLE_SHARE`
4. 如果找不到`TABLE_SHARE`, 则生成一个
5. 根据`TABLE_SHARE`, 生成一个`TABLE`
6. 维护好cache

如果找不到`TABLE_SHARE`
---

参看[`get_table_share_with_discover`](http://osxr.org/mysql/ident?_i=get_table_share_with_discover)

如果内存中找不到`TABLE_SHARE`, 则向存储引擎查询, 如果存储引擎可以提供, 则进行[discover](http://osxr.org/mysql/ident?_i=recover_from_failed_open)

关于死锁
---

table_cache 里有很多代码是关于死锁的处理, 其一个主要原因是因为 mysql 分为了sql层和存储引擎层, MDL的死锁检测限于sql层, 存储引擎层自带死锁检测, 但一个死锁如果跨过两层, 则需要特殊处理

