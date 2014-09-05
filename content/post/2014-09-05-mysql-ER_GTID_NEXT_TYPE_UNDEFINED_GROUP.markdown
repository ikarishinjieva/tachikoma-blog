+++
draft = false
title = "Mysql 出现ER_GTID_NEXT_TYPE_UNDEFINED_GROUP的一种可能"
date = 2014-09-05T22:00:00Z
tags = [ "mysql", "bug"]
+++

最近Mysql slave发生了一次下面的错误:

	When @@SESSION.GTID_NEXT is set to a GTID, you must explicitly set it to a different value after a COMMIT or ROLLBACK

因为没留下现场, 分析起来很困难. 从mysql bug库中刨出了一个类似的[bug 68525](http://bugs.mysql.com/bug.php?id=68525), 分析了这个bug的成因. 

BTW, 不幸的是分析完后觉得与之前碰到场景不一致.

下面将介绍这个bug的成因.

### bug描述

重现这个bug需满足下面的条件:

* relay-log-info-repository = TABLE
* gtid-mode = on
* binlog-format = ROW
* max_binlog_size 足够小, 我设置为 4096

用下面的脚本在master上创建**myisam**表并灌数据, slave上就会出现`ER_GTID_NEXT_TYPE_UNDEFINED_GROUP`

```
CREATE TABLE `item` (`id` int(11) NOT NULL AUTO_INCREMENT,`item` varchar(10), PRIMARY KEY (`id`)) ENGINE=myisam DEFAULT CHARSET=utf8 COLLATE=utf8_czech_ci;

insert into item(item) values ('test1') ;

insert into item(item) values ('test2') ;

insert into item(item) values ('test3') ;

insert into item(item) values ('test4') ;

insert into item(item) select item from item;

insert into item(item) select item from item;

insert into item(item) select item from item;

insert into item(item) select item from item;

insert into item(item) select item from item;

insert into item(item) select item from item;

insert into item(item) select item from item;

insert into item(item) select item from item;

insert into item(item) select item from item;

#最后一组数据是1024行
```

普遍的解决方法是在slave上`stop slave; start slave`就可以从这个错误中恢复, 但注意此时master和slave上数据是**不一致**的

### row event的拆分

进行更进一步的描述前, 先需要理解row event的拆分:

* 在master端, 当row event的大小超过`binlog-row-event-max-size`时, 会使用一个新的row event.  `binlog-row-event-max-size`默认大小为8k, 即如果更新1000行, 会被拆成若干个8k的row event
* 在master端, 无论`max_binlog_size`多小, 一次提交的row event都会存放在同一个binlog中, 即如果更新1000行, 所有的row event都会放在同一个binlog中 (即使更新的是myisam表)
* 在slave端, relay log以event为单位接受master发送的binlog, 如果当前relay log大小超过`max_relay_log_size`, relay log进行轮换. 即之前的1000行更新在slave端会被**拆分**到若干个relay log中. 本例中`max_relay_log_size = 0`, relay log的大小限制同`max_binlog_size`


### 错误发生在何处

理解了row event会被拆分到多个relay log中, 那从relay log的角度:

```
===
# relay-log.000001
GTID_desc event
BEGIN event
row_event 0
row_event 1
...
row_event x
ROTATE event
===
# relay-log.000002
Format_description_event
Previous-GTIDs
...
# <-- 错误发生在此处!
row_event x+1
...
COMMIT event
```

错误发生在新的relay-log执行第x+1个row_event之前, 发生错误时可以看到slave的`executed_gtid`已经按照GTID_desc event的描述更新了, 这意味着两件事情:

* 可能在relay-log轮换时发生了commit, 导致还未执行完的更新(只执行到了row_event x)将其gtid刷到了`executed_gtid`中,  这可能是bug发生的原因.
* 如果此时执行`stop slave; start slave`, 那么整个更新将被跳过, **这就是为什么可以从错误中恢复**. 但`row_event x`以后的更新将丢失, **造成数据不一致**.

### 为什么会抛出错误

检查一下`ER_GTID_NEXT_TYPE_UNDEFINED_GROUP`的抛出处
```
gtid_pre_statement_checks {
     …
     if (UNDEFINED_GROUP == gtid_next->type) {
          my_error(ER_GTID_NEXT_TYPE_UNDEFINED_GROUP, MYF(0), buf);
     }
     …
}
```

那设置`gtid_next->type = UNDEFINED_GROUP`的地方在

```
set_undefined() {
     if (type == GTID_GROUP)
          type= UNDEFINED_GROUP;
}
```

`set_undefined`被很多逻辑分支调用, 都是Mysql确定当前Gtid被使用完毕或者需要抛弃时被调用, 比如commit和rollback时.

那如之前的猜想, 在relay log 轮换时发生了commit, 就会`set_undefined`, `row_event x+1`执行前的检查就会抛出`ER_GTID_NEXT_TYPE_UNDEFINED_GROUP`.

用断点追踪一下也应正了这个猜想:

	#0  Gtid_specification::set_undefined (this=0x7f8e940011b8) at /opt/mysql-src-5.6.19/sql/rpl_gtid.h:2413
	#1  0x0000000000a0a9ed in Gtid_state::update_on_flush (this=0x2c14310, thd=0x7f8e940008c0)
	    at /opt/mysql-src-5.6.19/sql/rpl_gtid_state.cc:170
	#2  0x0000000000a4788d in MYSQL_BIN_LOG::write_cache (this=0x1826c00, thd=0x7f8e940008c0,
	    cache_data=0x7f8e94035b40) at /opt/mysql-src-5.6.19/sql/binlog.cc:5799
	#3  0x0000000000a3b803 in binlog_cache_data::flush (this=0x7f8e94035b40, thd=0x7f8e940008c0,
	    bytes_written=0x7f8ed5d9f0b0, wrote_xid=0x7f8ed5d9f107) at /opt/mysql-src-5.6.19/sql/binlog.cc:1227
	#4  0x0000000000a5088d in binlog_cache_mngr::flush (this=0x7f8e94035b40, thd=0x7f8e940008c0,
	    bytes_written=0x7f8ed5d9f108, wrote_xid=0x7f8ed5d9f107) at /opt/mysql-src-5.6.19/sql/binlog.cc:774
	#5  0x0000000000a48f46 in MYSQL_BIN_LOG::flush_thread_caches (this=0x1826c00, thd=0x7f8e940008c0)
	    at /opt/mysql-src-5.6.19/sql/binlog.cc:6368
	#6  0x0000000000a49195 in MYSQL_BIN_LOG::process_flush_stage_queue (this=0x1826c00,
	    total_bytes_var=0x7f8ed5d9f280, rotate_var=0x7f8ed5d9f27f, out_queue_var=0x7f8ed5d9f270)
	    at /opt/mysql-src-5.6.19/sql/binlog.cc:6424
	#7  0x0000000000a49eb7 in MYSQL_BIN_LOG::ordered_commit (this=0x1826c00, thd=0x7f8e940008c0, all=false,
	    skip_commit=false) at /opt/mysql-src-5.6.19/sql/binlog.cc:6841
	#8  0x0000000000a48e6a in MYSQL_BIN_LOG::commit (this=0x1826c00, thd=0x7f8e940008c0, all=false)
	    at /opt/mysql-src-5.6.19/sql/binlog.cc:6335
	#9  0x0000000000644bdb in ha_commit_trans (thd=0x7f8e940008c0, all=false, ignore_global_read_lock=true)
	    at /opt/mysql-src-5.6.19/sql/handler.cc:1436
	#10 0x0000000000a9214d in Rpl_info_table_access::close_table (this=0x32c1b20, thd=0x7f8e940008c0,
	    table=0x3371800, backup=0x7f8ed5da0520, error=false) at /opt/mysql-src-5.6.19/sql/rpl_info_table_access.cc:163
	#11 0x0000000000a9075f in Rpl_info_table::do_flush_info (this=0x32c1ba0, force=true)
	    at /opt/mysql-src-5.6.19/sql/rpl_info_table.cc:238
	#12 0x0000000000a7def4 in Rpl_info_handler::flush_info (this=0x32c1ba0, force=true)
	    at /opt/mysql-src-5.6.19/sql/rpl_info_handler.h:92
	#13 0x0000000000a842c9 in Relay_log_info::flush_info (this=0x3355240, force=true)
	    at /opt/mysql-src-5.6.19/sql/rpl_rli.cc:2028
	#14 0x0000000000a42871 in MYSQL_BIN_LOG::purge_first_log (this=0x3355980, rli=0x3355240, included=false)
	    at /opt/mysql-src-5.6.19/sql/binlog.cc:3966
	#15 0x0000000000a7805d in next_event (rli=0x3355240) at /opt/mysql-src-5.6.19/sql/rpl_slave.cc:7362
	#16 0x0000000000a6dd60 in exec_relay_log_event (thd=0x7f8e940008c0, rli=0x3355240)
	    at /opt/mysql-src-5.6.19/sql/rpl_slave.cc:3814
	#17 0x0000000000a73646 in handle_slave_sql (arg=0x2c197b0) at /opt/mysql-src-5.6.19/sql/rpl_slave.cc:5708
	#18 0x0000000000e1e0b1 in pfs_spawn_thread (arg=0x7f8eb0050080)
	    at /opt/mysql-src-5.6.19/storage/perfschema/pfs.cc:1860
	#19 0x00007f8f03ef89d1 in start_thread () from /lib64/libpthread.so.0
	#20 0x00007f8f02e62b5d in clone () from /lib64/libc.so.6

可以看到:
* relay log进行轮换时`purge_first_log`
* Rpl_info_table需要进行`flush_info`
* 导致了进行完整提交(`ordered_commit`), 此时会`set_undefined`

### 为什么relay log轮换会触发完整提交

下面代码来自`MYSQL_BIN_LOG::commit`:

```
  if (stuff_logged)
  {
    if (ordered_commit(thd, all))
      DBUG_RETURN(RESULT_INCONSISTENT);
  }
  else
  {
    if (ha_commit_low(thd, all))
      DBUG_RETURN(RESULT_INCONSISTENT);
  }
```

提交`Rpl_info_table`时, 如果真的有"货"要提交(`stuff_logged`), 就会用`ordered_commit`做完整提交(包括`set_undefined`); 否则, 用`ha_commit_low`仅做innodb层的提交.

所谓有"货"要提交, mysql源码的注释为:

>    We commit the transaction if:
>    - We are not in a transaction and committing a statement, or
>    - We are in a transaction and a full transaction is committed.
>    Otherwise, we accumulate the changes.

那么:
* 当前这个bug满足第一种情况
* 第二种情况解释了为什么使用innodb表时不会出现这个bug.

### 最后

最后验证一下`relay-log-info-repository=FILE`时不会触发这个bug的.

复盘一下:

* 同一个commit的多个row event会被拆分到不同的relay log中.
* 使用`relay-log-info-repository=TABLE`时, 轮换relay log会触发commit.
* 由于是myisam表, 则触发了一个完整commit (`ordered_commit`). 会重置gtid状态为undefined.
* 下一个relay log执行时, 发现gtid状态异常报错.
* `stop slave; start slave`后, 由于gtid已经更新, 整个commit会被跳过, 造成数据丢失.

简单地说就是`relay-log-info-repository=TABLE`的交易性和myisam的非交易性在轮换relay log时的冲突.