+++
draft = false
title = "Mysql 出现ER_GTID_NEXT_TYPE_UNDEFINED_GROUP的第二种可能"
date = 2014-09-17T09:33:00Z
tags = [ "mysql", "bug"]
+++

之前[讨论](http://ikarishinjieva.github.io/tachikoma-blog/post/2014-09-05-mysql-er_gtid_next_type_undefined_group/)过Mysql出现以下错误的一种可能:

	When @@SESSION.GTID_NEXT is set to a GTID, you must explicitly set it to a different value after a COMMIT or ROLLBACK

下面描述的另一种可能来自于taobao的[Mysql内核月报](http://mysql.taobao.org/index.php/MySQL内核月报_2014.09). 主要涉及到`insert delayed`语句.

### 关于`insert delayed`

下面是关于`insert delayed`的几个描述:

* `insert delayed`对客户端立刻返回, 而将实际数据任务排队到合适的时候才进行.
* `insert delayed`仅支持MyISAM表, 且在Mysql 5.6.6及以后deprecate, 但在目前Mysql 5.6.20中仍可使用.
* 对于Mixed和Row格式的binlog, `insert delayed`将使用Row格式. 而对于Statement格式, `insert delayed`将退化成普通的`insert`语句. (`sql_insert.cc:upgrade_lock_type`)

### bug描述

在master上执行以下脚本, 可以在slave上看到复制的error:

```
/opt/mysql/bin/mysql -uroot -h127.0.0.1 -e "CREATE TABLE a (a int) ENGINE=MyISAM"

for i in {1..2}
do
/opt/mysql/bin/mysql -uroot -h127.0.0.1 -e "insert delayed into test.a values(1)" &
done
```

### 分析

`insert delayed`的执行可以看做分为两个部分: 生产者和消费者. 

同时执行的两个`insert delayed`, 会触发两个生产者线程将两次执行排队到队列中, 等待消费者进行消费

消费者线程的大概流程是:

```
handle_delayed_insert
     Delayed_insert::handle_inserts
          while(row = rows.get()) {
               write binlog
               write table
          }
     trans_commit_stmt
```

其形成的binlog形式是:

```
GTID_DESC
BEGIN
row_event 1
row_event 2
COMMIT
```

这段binlog在slave上重放时, row_event 1结束后会进行commit, 对GTID执行`set_undefined` (如果不理解这一段, 请参看[之前的讨论](http://ikarishinjieva.github.io/tachikoma-blog/post/2014-09-05-mysql-er_gtid_next_type_undefined_group/))

执行row_event 2时就找不到GTID的描述, 故error

### 何时commit

上面的分析有一部分是有点奇怪的, 就是``row_event 1结束后会进行commit".

对比另外一个场景, 如果进行一个大的insert, 比如`insert into a values(1),(2),(3),...,(100000)`, 形成的binlog形式与上面一模一样, 但仅在最后一个row_event时进行commit

造成这种差异的原因在于标识`STMT_END_F`,  在bug的场景中,  两个row_event都带有标识`STMT_END_F`, 故会在每个row_event执行后进行commit


### 复盘

这个bug主要的成因是两个并行`insert delayed`会组合在一起向master提交, 且提交成功. 而根据binlog, slave执行时会进行两次commit, 但共用了同一个GTID_DESC, 所以会发生错误.
