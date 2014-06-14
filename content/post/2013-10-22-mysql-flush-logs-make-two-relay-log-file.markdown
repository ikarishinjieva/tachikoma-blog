+++
draft = false
title = "Mysql 5.6.12 master上flush logs在slave上产生两个relay-log"
date = 2013-10-22T21:42:00Z
tags = [ "mysql", "replication"]
+++

现象
---

一个碰巧观察到的有趣的现象：mysql 5.6.12 在master上flush logs，在slave上会观察到两个新的relay-log file

举例：

slave-relay-bin.000092

     FD event
     Rotate to mysql-bin.000056
     Rotate to slave-relay-bin.000093

slave-relay-bin.000093

     FD event slave
     Rotate to mysql-bin.000056
     FD event master
     bla bla…
     
可以看到000092这个relay log相当多余。这个现象并不会影响replication的正确性，只是让有强迫症的人有点狂躁

探索
---
在master上net_serv.cc:my_net_write打断点，可以观察到master的确发出了以下三个事件

* ROTATE_EVENT

backtrace

    #0  my_net_write (net=0x1ea2858, packet=0x7fffa4002b70 "", len=48)
        at /home/vagrant/mysql-5.6.12/sql/net_serv.cc:284
    #1  0x0000000000a48b05 in mysql_binlog_send (thd=0x1ea2600, log_ident=0x7fffa4004c60 "mysql-bin.000052", pos=167,
        slave_gtid_executed=0x0) at /home/vagrant/mysql-5.6.12/sql/rpl_master.cc:1336
    #2  0x0000000000a46ad2 in com_binlog_dump (thd=0x1ea2600, packet=0x1ea5d21 "", packet_length=26)
        at /home/vagrant/mysql-5.6.12/sql/rpl_master.cc:746
    #3  0x00000000007d1ab9 in dispatch_command (command=COM_BINLOG_DUMP, thd=0x1ea2600, packet=0x1ea5d21 "",
        packet_length=26) at /home/vagrant/mysql-5.6.12/sql/sql_parse.cc:1534
    #4  0x00000000007d017b in do_command (thd=0x1ea2600) at /home/vagrant/mysql-5.6.12/sql/sql_parse.cc:1036
    #5  0x0000000000797a08 in do_handle_one_connection (thd_arg=0x1ea2600)
        at /home/vagrant/mysql-5.6.12/sql/sql_connect.cc:977
    #6  0x00000000007974e4 in handle_one_connection (arg=0x1ea2600)
        at /home/vagrant/mysql-5.6.12/sql/sql_connect.cc:893
    #7  0x0000000000aea87a in pfs_spawn_thread (arg=0x1e7aa80)
        at /home/vagrant/mysql-5.6.12/storage/perfschema/pfs.cc:1855
    #8  0x00007ffff7bc7851 in start_thread () from /lib64/libpthread.so.0
    #9  0x00007ffff6b3290d in clone () from /lib64/libc.so.6

* 第二个ROTATE_EVENT

backtrace

    #0  my_net_write (net=0x1ea2858, packet=0x7fffa4002ab0 "", len=48)
        at /home/vagrant/mysql-5.6.12/sql/net_serv.cc:284
    #1  0x0000000000a45f04 in fake_rotate_event (net=0x1ea2858, packet=0x1ea2be8,
        log_file_name=0x7fffc94ff270 "./mysql-bin.000056", position=4, errmsg=0x7fffc94ffdb0,
        checksum_alg_arg=1 '\001') at /home/vagrant/mysql-5.6.12/sql/rpl_master.cc:395
    #2  0x0000000000a4a33d in mysql_binlog_send (thd=0x1ea2600, log_ident=0x7fffa4004c60 "mysql-bin.000052", pos=167,
        slave_gtid_executed=0x0) at /home/vagrant/mysql-5.6.12/sql/rpl_master.cc:1728
    #3  0x0000000000a46ad2 in com_binlog_dump (thd=0x1ea2600, packet=0x1ea5d21 "", packet_length=26)
        at /home/vagrant/mysql-5.6.12/sql/rpl_master.cc:746
    #4  0x00000000007d1ab9 in dispatch_command (command=COM_BINLOG_DUMP, thd=0x1ea2600, packet=0x1ea5d21 "",
        packet_length=26) at /home/vagrant/mysql-5.6.12/sql/sql_parse.cc:1534
    #5  0x00000000007d017b in do_command (thd=0x1ea2600) at /home/vagrant/mysql-5.6.12/sql/sql_parse.cc:1036
    #6  0x0000000000797a08 in do_handle_one_connection (thd_arg=0x1ea2600)
        at /home/vagrant/mysql-5.6.12/sql/sql_connect.cc:977
    #7  0x00000000007974e4 in handle_one_connection (arg=0x1ea2600)
        at /home/vagrant/mysql-5.6.12/sql/sql_connect.cc:893
    #8  0x0000000000aea87a in pfs_spawn_thread (arg=0x1e7aa80)
        at /home/vagrant/mysql-5.6.12/storage/perfschema/pfs.cc:1855
    #9  0x00007ffff7bc7851 in start_thread () from /lib64/libpthread.so.0
    #10 0x00007ffff6b3290d in clone () from /lib64/libc.so.6
* FORMAT_DESCRIPTION_EVENT

可以看到第一个ROTATE_EVENT是由flush logs发出的，第二个ROTATE_EVENT是fake_rotate_event

关于fake_rotate_event
---
以前也[吐槽](http://ikarishinjieva.github.io/blog/blog/2013/10/16/mysql-mysql_binlog_send-src/)过fake_rotate_event

master在binlog切换时（不一定是手工flush，也可能是重启，或者容量达到限制）一定要多发一个rotate event，原因如源码rpl_master.cc:mysql_binlog_send中的注释


      /*
        Call fake_rotate_event() in case the previous log (the one which
        we have just finished reading) did not contain a Rotate event.
        There are at least two cases when this can happen:

        - The previous binary log was the last one before the master was
          shutdown and restarted.

        - The previous binary log was GTID-free (did not contain a
          Previous_gtids_log_event) and the slave is connecting using
          the GTID protocol.

        This way we tell the slave about the new log's name and
        position.  If the binlog is 5.0 or later, the next event we
        are going to read and send is Format_description_log_event.
      */
      if ((file=open_binlog_file(&log, log_file_name, &errmsg)) < 0 ||
          fake_rotate_event(net, packet, log_file_name, BIN_LOG_HEADER_SIZE,
                            &errmsg, current_checksum_alg))

主要是解决之前没有rotate event发送的场景

虽然非常想吐槽，但是我也想不出更好的办法