+++
draft = false
title = "Mysql 出现ER_GTID_NEXT_TYPE_UNDEFINED_GROUP的第三种可能"
date = 2014-11-13T19:44:00Z
tags = [ "mysql", "bug", "replication"]
+++

之前讨论过两种出现ER_GTID_NEXT_TYPE_UNDEFINED_GROUP的可能([可能1](http://ikarishinjieva.github.io/tachikoma-blog/post/2014-09-05-mysql-er_gtid_next_type_undefined_group/)和[可能2](http://ikarishinjieva.github.io/tachikoma-blog/post/2014-09-17-mysql-er_gtid_next_type_undefined_group-2/))

但都不是之前在线上环境见到的状况, 前几天QA重现了线上的情况, 经过几天的折腾, 终于找到了原因.


###结论

先说结论, Mysql 5.6.21以下的Mysql版本会出现这个错误, 导致复制不正常, 发生`ER_GTID_NEXT_TYPE_UNDEFINED_GROUP`错误, 而如果强行`start slave`, 会永久丢失一个事务, 导致主从数据不一致.

这个错误的发生概率还是较大的, 如果使用了GTID, 并且使用了`master_auto_position`来建立复制, 那建议升级到Mysql 5.6.21.

###如何重现

先用下面的patch修改Mysql源码, 这段patch用于增加debug点 (如果不想修改源码, 也可用gdb手工模仿):

    --- rpl_slave.cc.orig     2014-11-12 16:03:36.000000000 +0800
	+++ rpl_slave.cc     2014-11-12 16:05:18.000000000 +0800
	@@ -4378,6 +4378,14 @@
	       THD_STAGE_INFO(thd, stage_queueing_master_event_to_the_relay_log);
	       event_buf= (const char*)mysql->net.read_pos + 1;
	       DBUG_PRINT("info", ("IO thread received event of type %s", Log_event::get_type_str((Log_event_type)event_buf[EVENT_TYPE_OFFSET])));
	+
	+      DBUG_EXECUTE_IF("stop_io_before_reading_xid_log_event",
	+        if (event_buf[EVENT_TYPE_OFFSET] == XID_EVENT) {
	+           thd->killed= THD::KILLED_NO_VALUE;
	+           goto err;
	+        }
	+      );
	+
	       if (RUN_HOOK(binlog_relay_io, after_read_event,
	                    (thd, mi,(const char*)mysql->net.read_pos + 1,
	                     event_len, &event_buf, &event_len)))

然后执行下面的mysql-test脚本:

    --source include/have_debug.inc
    --source include/have_gtid.inc
    
    --disable_warnings
    --source include/master-slave.inc
    --enable_warnings
    
    --connection master
    create table test.a(a int) engine=innodb;
    flush logs;
    --source include/sync_slave_sql_with_master.inc
    
    --connection slave
    stop slave;
    set global debug="d,stop_io_before_reading_xid_log_event";
    
    --connection master
    begin;
    insert into test.a values(1);
    insert into test.a values(2);
    commit;
    
    --connection slave
    start slave io_thread;
    --let $slave_param= Slave_IO_Running
    --let $slave_param_value= No
    --source include/wait_for_slave_param.inc
    
    --connection slave
    set global debug="";
    
    start slave;
    --let $slave_param= Slave_SQL_Running
    --let $slave_param_value= No
    --source include/wait_for_slave_param.inc
    
    --let $errno= query_get_value("SHOW SLAVE STATUS", "Last_Errno", 1)
    --if ($errno != "1837") {
    	--echo Got unexpect errno=$errno
    	--die
    }
    --echo Got Slave SQL error 1837
    
    # Cleanup
    --connection master
    drop table test.a;
    
    --connection slave
    set global debug="";
    start slave;
    --source include/sync_slave_sql_with_master.inc
    --source include/rpl_end.inc

在Mysql 5.6.19/5.6.20上都能成功重现.

###Bug分析

重现这个bug需要具备以下前提条件:

1. Mysql使用GTID
2. Mysql复制使用了`master_auto_position`

对重现的每个步骤进行说明:

---
首先需要在Master上进行`flush logs`, 这样生成的binlog和一般binlog的区别是`created`段值为0 (**正常的binlog rotate也会产生这个效果**). 关于`created`在Mysql源码中是如下说明的:

    /*
    If this event is at the start of the first binary log since server
    startup 'created' should be the timestamp when the event (and the
    binary log) was created.  In the other case (i.e. this event is at
    the start of a binary log created by FLUSH LOGS or automatic
    rotation), 'created' should be 0.  This "trick" is used by MySQL
    >=4.0.14 slaves to know whether they must drop stale temporary
    tables and whether they should abort unfinished transaction.
    ...
    */

额外一提, `mysqlbinlog`在解析binlog时对`created`段解析是有问题的, 建议直接使用`mysqlbinlog --hexdump`来看

---
然后在Slave上设置新加的debug点`stop_io_before_reading_xid_log_event`, 并开启IO复制线程.

在Master上插入以下事务:

    begin;
    insert into test.a values(1);
    insert into test.a values(2);
    commit;
    
这样IO复制线程会在commit之前停下来, 假设正在使用relay-log.000001, 那这个relay log中就只含有begin和两个insert

---
接下来去掉debug点,再次开启IO复制线程.

由于Mysql复制使用了`master_auto_position`(前提条件2), 就会重传整个事务, 得到以下的relay log:

    ---relay-log.000001
    ...
    GTID
    begin;
    insert into test.a values(1);
    insert into test.a values(2);
    ROTATE
    
    --relay-log.000002
    slave FDE (Format_description_event)
    Previous-gtid
    Rotate
    master FDE (created=0)
    Rotate'
    Rotate''
    GTID
    begin;
    insert into test.a values(1);
    insert into test.a values(2);
    commit;
    
两点说明:

1. 如果不使用`master_auto_position`, 就不会重传整个事务, 而是断点续传
2. relay-log.000002开头好几个rotate看起来比较复杂, 可以先忽略这个细节, 对整个bug没有影响
得到上面的relay-log后, 如果开启sql线程会发生什么呢? 

---

如果之前没有将`created`段置为0的那一步, 一切运行都会是正常的, 原因是在master FDE的处理中:

    //Format_description_log_event::do_apply_event
      /*
        As a transaction NEVER spans on 2 or more binlogs:
        if we have an active transaction at this point, the master died
        while writing the transaction to the binary log, i.e. while
        flushing the binlog cache to the binlog. XA guarantees that master has
        rolled back. So we roll back.
        Note: this event could be sent by the master to inform us of the
        format of its binlog; in other words maybe it is not at its
        original place when it comes to us; we'll know this by checking
        log_pos ("artificial" events have log_pos == 0).
      */
      if (!is_artificial_event() && created && thd->transaction.all.ha_list)
      {
        /* This is not an error (XA is safe), just an information */
        rli->report(INFORMATION_LEVEL, 0,
                    "Rolling back unfinished transaction (no COMMIT "
                    "or ROLLBACK in relay log). A probable cause is that "
                    "the master died while writing the transaction to "
                    "its binary log, thus rolled back too."); 
        const_cast<Relay_log_info*>(rli)->cleanup_context(thd, 1);
      }
    
如果当前存在事务(`thd->transaction.all.ha_list`), 且master FDE标明它是master启动时产生的binlog, 那slave会将当前事务回滚掉(`cleanup_context`).

如果master在写入binlog时崩溃, master重启后会回滚binlog,那slave也会相应产生回滚.

由于我们之前设置了`created`为0, 这个机制就不起作用. 之后会发生什么呢?

---

sql线程是这样执行的:

1. 从relay-log.000001往下执行, 进入事务
2. 发现Rotate, 轮换到relay-log.000002, 但事务并没有结束, 就仿佛一个事务跨了两个relay log(一个事务是可以跨多个relay log)
3. master FDE的保护机制由于FDE的`created`为0而失效, 可以继续执行, 且仍在事务中
4. GTID event将当前线程的`GTID_NEXT`值重置, 但**并不会回滚事务**
5. BEGIN event会将当前事务提交, 清掉`GTID_NEXT`, 并开始新的事务
6. 之后的insert发现`GTID_NEXT`已经为空, 故报了`ER_GTID_NEXT_TYPE_UNDEFINED_GROUP`的错误

---

需要说明一下BEGIN event为什么会提交事务. 这也很好理解, 如果执行下面的语句:

    BEGIN;
    insert into test.a values(444);
    BEGIN;
    
在Mysql中正常的流程是insert会被隐式提交. 但在执行relay log时, 这样的处理就会导致新的事务丢失了GTID事件.

###Mysql 5.6.21的修复

之前我们提到了: GTID event将当前线程的`GTID_NEXT`值重置, 但**并不会回滚事务**

而Mysql 5.6.21进行的修复就是让GTID event进行事务回滚, 代码如下:

    //Gtid_log_event::do_apply_event
    if (thd->owned_gtid.sidno)
    {
        /*
    	  Slave will execute this code if a previous Gtid_log_event was applied
    	  but the GTID wasn't consumed yet (the transaction was not committed
    	  nor rolled back).
    	  On a client session we cannot do consecutive SET GTID_NEXT without
    	  a COMMIT or a ROLLBACK in the middle.
    	  Applying this event without rolling back the current transaction may
    	  lead to problems, as a "BEGIN" event following this GTID will
    	  implicitly commit the "partial transaction" and will consume the
    	  GTID. If this "partial transaction" was left in the relay log by the
    	  IO thread restarting in the middle of a transaction, you could have
    	  the partial transaction being logged with the GTID on the slave,
    	  causing data corruption on replication.
    	*/
    	if (thd->transaction.all.ha_list)
    	{
    	  /* This is not an error (XA is safe), just an information */
    	  rli->report(INFORMATION_LEVEL, 0,
    	              "Rolling back unfinished transaction (no COMMIT "
    	              "or ROLLBACK in relay log). A probable cause is partial "
    	              "transaction left on relay log because of restarting IO "
    	              "thread with auto-positioning protocol.");
    	  const_cast<Relay_log_info*>(rli)->cleanup_context(thd, 1);
    	}
        gtid_rollback(thd);
    }
    
其中`gtid_rollback`是在之前版本中就有, 是用来回滚GTID信息的. 而`if (thd->transaction.all.ha_list)`中的是Mysql 5.6.21的修复部分.

    

