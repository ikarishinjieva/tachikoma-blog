+++
draft = false
title = "Mysql rpl_slave.cc:handle_slave_io 源码的一些个人分析"
date = 2013-10-20T20:17:00Z
tags = [ "mysql", "replication"]
+++

读了rpl_slave.cc:handle_slave_io的源码（Mysql 5.6.11），总结一下

函数概述
---
handle_slave_io是slave io_thread的主函数，函数逻辑入口为rpl_slave.cc:start_slave_threads

主体结构
---

```
handle_slave_io(master_info) {
     3955 bla bla…
     4016 fire HOOK binlog_relay_io.thread_start
     4032 与master建立连接
    (4047 设置max_packet_size)
     4073 get_master_version_and_clock,
          在master上：
          通过SELECT UNIX_TIMESTAMP()获取server timestamp
          通过SHOW VARIABLES LIKE 'SERVER_ID'获取server id
          SET @master_heartbeat_period= ?
          SET @master_binlog_checksum= @@global.binlog_checksum
          SELECT @master_binlog_checksum获取master binlog checksum
          SELECT @@GLOBAL.GTID_MODE
     4075 get_master_uuid
          在master上“SHOW VARIABLES LIKE 'SERVER_UUID'”
     4077 io_thread_init_commands
          在master上“SET @slave_uuid= '%s'”
     4106 register_slave_on_master
          向master发送COM_REGISTER_SLAVE
     4133 while (!io_slave_killed(thd,mi))
     4134 {
     4136      request_dump
               向master发送COM_BINLOG_DUMP_GTID/COM_BINLOG_DUMP
     4159      while (!io_slave_killed(thd,mi))
     4160      {
     4169           read_event，此为阻塞方法，会阻塞等待有新数据包传入
     4184          {
                         一些包错误的处理，包括packet too large / out of resource等
     4213          }
     4219          fire HOOK binlog_relay_io.after_read_event
     4232          queue_event，将event放入relay log写buf
     4240          fire HOOK binlog_relay_io.after_queue_event
     4250          flush_master_info，将master_info和relay log刷到disk上
                   此处，先刷relay log，后刷master_info。这样意外的故障可以通过重连恢复机制来恢复。
                   若先刷master_info，后刷relay log，意外故障时master_info已经更新，比如(0-100, 100-200)，而数据丢失，仅有(0-100)，恢复的replication会从200开始。整个relay log会成为(0-100, 200-)，中间数据会丢失。

     4286          若relay log达到容量限制，则wait_for_relay_log_space
     4292      }
     4293 }
     4296 之后都是收尾操作        
}
```

一些重点
---
1. 此处不分析锁什么的，因为看不懂
2. 4047 设置max_packet_size的目的不明
3. 4073 开始slave会向master直接发送一些sql，然后解析返回。而不是包装在某个包的某个字段里，用一些预定义的变量来传递结果。<br/>这种设计一下就觉得山寨起来。<br/>后经同事 @神仙 指点，mysql这样做貌似是为了兼容性，免得数据包格式被改来改去。<br/>（看到mysql里大量的兼容代码都拿来处理包结构的问题，最极品的可能是莫过于LOG_EVENT_MINIMAL_HEADER_LEN了）<br/>在对流量影响不大的情况下，直接用sql反复查询的确是个好的解决手法
4. 4250 将master_info和relay log刷到disk上。<br/>先刷relay log，后刷master_info。这样意外的故障可以通过relay log恢复机制来恢复。<br/>若先刷master_info，后刷relay log，意外故障时master_info已经更新，比如(0-100, 100-200)，而数据(100-200)丢失，仅有(0-100)，恢复的replication会从200开始。整个relay log会成为(0-100, 200-)，中间数据会丢失。

start slave时slave向master发送的事件
---
   * 
SELECT UNIX_TIMESTAMP() (rpl_slave.cc:get_master_version_and_clock)
   * SHOW VARIABLES LIKE 'SERVER_ID' (rpl_slave.cc:get_master_version_and_clock)
   * SET @master_heartbeat_period=? (rpl_slave.cc:get_master_version_and_clock)
   * SET @master_binlog_checksum= @@global.binlog_checksum (rpl_slave.cc:get_master_version_and_clock)
   * SELECT @master_binlog_checksum (rpl_slave.cc:get_master_version_and_clock)
   * SELECT @@GLOBAL.GTID_MODE (rpl_slave.cc:get_master_version_and_clock)
   * SHOW VARIABLES LIKE 'SERVER_UUID' （rpl_slave.cc:get_master_uuid）

   * SET @slave_uuid= '%s'（rpl_slave.cc:io_thread_init_commands)
   * COM_REGISTER_SLAVE(rpl_slave.cc:register_slave_on_master)
   * COM_BINLOG_DUMP(rpl_slave.cc:request_dump)

master与slave的时间差
---
可以看到slave获得master的时间方法就是直接下sql，完全忽略网络延迟等等等等，属于不精准的时间

[这篇文章](http://guduwhuzhe.iteye.com/blog/1901707)从源码级别分析了Seconds_Behind_Master的来源，也给出了备库延迟跳跃的原因。总的来说就是Seconds_Behind_Master不可信。