+++
draft = false
title = "Mysql 5.6的crash-safe replication中与relay-log.info相关的部分"
date = 2014-08-28T20:18:00Z
tags = [ "mysql", "crash safe", "bug"]
+++

这篇blog目的是记录一下对Mysql 5.6 crash-safe replication的学习, 以及报给mysql的一个相关[bug](http://bugs.mysql.com/bug.php?id=73720)

先推荐Mats Kindahl写的关于crash safe的[科普](http://mysqlmusings.blogspot.com/2011/04/crash-safe-replication.html)

### crash-safe

按照Mats Kindahl的分类, 在此仅涉及"crash-safe slaves"中与relay-log.info相关的部分

Mysql crash-safe的名字起得并不好, 正确的名字应该是`crash-safe-only-for-DML-of-innodb`

涉及到DDL或非transactional型/非XA型的存储引擎时crash就不safe了, 比如这个[bug](http://bugs.mysql.com/bug.php?id=69444)

### bug

为了达成`crash-safe-only-for-DML-of-innodb`,  需要开启`relay-log-info-repository = TABLE`.

简单说明一下DDL/transactional DML/non-transactional DML的binlog event执行的区别:

1. DDL: `Query_event(DDL)`
2. transactional DML: `Query_event(Begin)` -> `Query_event(DML)` -> `Xid_event`
3. non-transactional DML: `Query_event(Begin)` -> `Query_event(DML)` -> `Query_event(Commit)`

其中`Query_event`中不会强制刷盘, 即`inc_group_relay_log_pos`中调用的`flush_info(FALSE)`; 而`Xid_event`会强制刷盘.

如果使用`relay-log-info-repository=FILE`, 不强制刷盘时会进行`flush_io_cache`, 强制刷盘时进行`my_sync` (`Rpl_info_file::do_flush_info`)

如果使用`relay-log-info-repository=TABLE`, 不强制刷盘时什么都不会做, 强制刷盘时才会更新表

也就是说仅执行DDL/non-transactional DML时, `slave_relay_log_info`的信息不会更新, 与`SHOW SLAVE STATUS`中的信息不同

报给了mysql一个[bug](http://bugs.mysql.com/bug.php?id=73720), 并被接受

结论是谨慎使用`slave_relay_log_info`中的值