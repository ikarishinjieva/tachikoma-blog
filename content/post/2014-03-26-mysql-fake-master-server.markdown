+++
draft = false
title = "mysql, 利用假master重放binlog"
date = 2014-03-26T20:08:00Z
tags = [ "mysql", "replication", "binlog"]
+++

场景
---

这次想解决的场景是想在一个mysqld实例上重放一些来自于其他实例的binlog, 传统的方法是`mysqlbinlog`. 但是`mysqlbinlog`会带来一些问题, 比如这个[bug](http://bugs.mysql.com/bug.php?id=33048)

后同事转给我一种利用[复制重放binlog的方法](http://www.orczhou.com/index.php/2013/11/use-mysql-replication-to-recove-binlog/), 其中提到两种方式: 

* 第一种是修改relay log的信息, 将binlog作为relay log来放. 这是种很好的方法, 缺点是`mysqld`需要停机重启. 如果不重启, server中对于`relay-log.index`和`relay-log.info`等的缓存不会刷新.
* 第二种是起另外一个mysqld实例, 将binlog作为relay log, 再将此实例作为master, 向目标实例进行复制. 这种方式的缺点是作为中间人的mysqld实例需要消耗资源

于是想办法将第二种方法进行改进, 即制造一个假的master, 实现简单的复制协议, 直接将binlog复制给目标mysqld实例. 与第二种方式相比, 好处在于只使用少量资源 (一个端口, 一点用来读文件的内存).


实现
---

实现参看我的[github](https://github.com/ikarishinjieva/mysql_binlog_utils/blob/master/fake_master_server.go)

**注意: 此实现仅适用于mysql 5.5.33, 其它版本未测试**

由于[mysql internals](http://dev.mysql.com/doc/internals/en/client-server-protocol.html) 已经将mysql的网络协议写的比较详细, 需要做的只是起一个tcp的server, 同目标mysqld实例进行交互即可.

此处逐层介绍实现, 将忽略不需要特别注意的部分. 为了简单, 将binlog的来源mysqld实例称为A, 目标mysqld实例称为B, 假master称为T.

目标就是讲从A获得的binlog文件, 通过T, 在B上重放出来

从B发起`start slave`, 到T真正向B复制数据, 需要下面两个阶段

.1. Handshake Phase

.2. Replication Phase

先介绍Handshake Phase, 有以下步骤

.1.1 B执行`start slave`, 此时B向T建立一个TCP连接

.1.2 T向B发送handshake packet

.1.3 B向T回复handshake packet response

.1.4 T向B发送ok packet

在Replication Phase, 有以下步骤

.2.1 B向T查询`SELECT UNIX_TIMESTAMP()`

.2.2 B向T查询`SHOW VARIABLES LIKE 'SERVER_ID'`

.2.3 B向T执行`SET @master_heartbeat_period= `

.2.4 B向T发送COM_REGISTER_SLAVE packet, 得到T回复的ok packet

.2.5 B向T发送COM_BINLOG_DUMP packet, T开始向B逐一发送binlog event packet

到目前为止, 所有的packet定义都可以在[mysql internals](http://dev.mysql.com/doc/internals/en/client-server-protocol.html), 逐一实现即可. 这里只简述一些处理packet时需要注意的细节.

处理packet时需要注意的细节
---

* 所有的packet都会包装一个[header](http://dev.mysql.com/doc/internals/en/mysql-packet.html), 其中包括packet payload(不包括header)的大小, 和序号
* 对于序号的处理, 比如2.2中B向T查询`SHOW VARIABLES LIKE 'SERVER_ID'`, B向T发送的第一个包序号为0, T向B回复的几个包序号依次递增为1,2,3...
* 注意数据类型, 仅整数, mysql的协议里有[定长整数](http://dev.mysql.com/doc/internals/en/integer.html)和变长整数(length encoded integer), 需要特别留意packet payload的类型描述
* 说明一下[query response packet](http://dev.mysql.com/doc/internals/en/com-query-response.html#packet-COM_QUERY_Response). 比如B向T做一个查询, T将通过query response packet来返回查询结果. 需要说明的是, 如果查询结果为空 (比如`SET @master_heartbeat_period= ?`的结果), 仅需返回`COM_QUERY_RESPONSE`, 后面不需要跟着空的column定义和row数据

对超大packet的支持
---

当一个packet过大 (超过`1<<24-1`byte ~= 16 MB) 时, 传输需要对packet进行切割, 参看[这里](http://dev.mysql.com/doc/internals/en/sending-more-than-16mbyte.html)

注意, 在A上生成binlog时, 是可以容纳大于16MB的packet的, 也就是原binlog里存在超大的event, 需要在传输时加以限制

切割packet没什么特别之处, 仅需要注意包格式, 一个20MB的event的传输packet格式举例为 (此处用`16MB`便于描述, 应为`1<<24-1`byte):

```
    packet 1
        4字节 packet header
        1字节 值为[00], 是binlog event的特征标志
        16MB-1字节 为第一段数据
        
    packet 2
        4字节 packet header
        20MB-16MB+1字节 为第二段数据
```
        
需要注意的是之后的packet时不带有[00]特征位的. 而包的大小计算范围为**除去前4字节**的全部字节

一些资料
---

除上文提到的资料, 还推荐[MySQL通讯协议研究系列](http://boytnt.blog.51cto.com/966121/1279318), 会对包格式有个直观感觉

Trouble shooting
---

在整个过程中, 有时候需要`gdb`到`mysqld`里来了解通讯协议的工作机制, 这里记录几个常用的函数入口点

.1. slave连接到master时

```
    #0  wait_for_data (fd=21, timeout=3600) at /vagrant/mysql-5.5.35/sql-common/client.c:208
    #1  0x00000000007316aa in my_connect (fd=21, name=0x7fa074004fd0, namelen=16, timeout=3600) at /vagrant/mysql-5.5.35/sql-common/client.c:187
    #2  0x00000000007363cb in mysql_real_connect (mysql=0x7fa074004960, host=0x3959cc8 "192.168.56.1", user=0x3959d05 "repl", passwd=0x3959d36 "", db=0x0, port=3306, unix_socket=0x0, client_flag=2147483648)
        at /vagrant/mysql-5.5.35/sql-common/client.c:3282
    #3  0x000000000057f138 in connect_to_master (thd=0x7fa074000a40, mysql=0x7fa074004960, mi=0x3959640, reconnect=false, suppress_warnings=false) at /vagrant/mysql-5.5.35/sql/slave.cc:4297
    #4  0x000000000057edd1 in safe_connect (thd=0x7fa074000a40, mysql=0x7fa074004960, mi=0x3959640) at /vagrant/mysql-5.5.35/sql/slave.cc:4233
    #5  0x000000000057b15c in handle_slave_io (arg=0x3959640) at /vagrant/mysql-5.5.35/sql/slave.cc:2851
    #6  0x00007fa096751851 in start_thread () from /lib64/libpthread.so.0
    #7  0x00007fa0954a690d in clone () from /lib64/libc.so.6
```

.2. handshake phase

```
    #0  send_server_handshake_packet (mpvio=0x7fa0942eb450, data=0x391e5b4 "=!-\\gq$\\%>J8z}'EgVW5", data_len=21) at /vagrant/mysql-5.5.35/sql/sql_acl.cc:8084
    #1  0x000000000059a87c in server_mpvio_write_packet (param=0x7fa0942eb450, packet=0x391e5b4 "=!-\\gq$\\%>J8z}'EgVW5", packet_len=21) at /vagrant/mysql-5.5.35/sql/sql_acl.cc:9082
    #2  0x000000000059bc99 in native_password_authenticate (vio=0x7fa0942eb450, info=0x7fa0942eb468) at /vagrant/mysql-5.5.35/sql/sql_acl.cc:9713
    #3  0x000000000059ad86 in do_auth_once (thd=0x391cc70, auth_plugin_name=0x1026760, mpvio=0x7fa0942eb450) at /vagrant/mysql-5.5.35/sql/sql_acl.cc:9336
    #4  0x000000000059b23a in acl_authenticate (thd=0x391cc70, connect_errors=0, com_change_user_pkt_len=0) at /vagrant/mysql-5.5.35/sql/sql_acl.cc:9472
    #5  0x00000000006d9eb5 in check_connection (thd=0x391cc70) at /vagrant/mysql-5.5.35/sql/sql_connect.cc:575
    #6  0x00000000006d9ffc in login_connection (thd=0x391cc70) at /vagrant/mysql-5.5.35/sql/sql_connect.cc:633
    #7  0x00000000006da5ba in thd_prepare_connection (thd=0x391cc70) at /vagrant/mysql-5.5.35/sql/sql_connect.cc:789
    #8  0x00000000006daa28 in do_handle_one_connection (thd_arg=0x391cc70) at /vagrant/mysql-5.5.35/sql/sql_connect.cc:855
    #9  0x00000000006da583 in handle_one_connection (arg=0x391cc70) at /vagrant/mysql-5.5.35/sql/sql_connect.cc:781
    #10 0x00007fa096751851 in start_thread () from /lib64/libpthread.so.0
    #11 0x00007fa0954a690d in clone () from /lib64/libc.so.6
```
    
.3. query时回复column定义

```
    #0  Protocol::send_result_set_metadata (this=0x3767610, list=0x3769328, flags=5)
        at /vagrant/mysql-5.5.35/sql/protocol.cc:677
    #1  0x00000000005c6745 in select_send::send_result_set_metadata (this=0x7f350c001658, list=..., flags=5)
        at /vagrant/mysql-5.5.35/sql/sql_class.cc:2132
    #2  0x000000000062895a in JOIN::exec (this=0x7f350c001678) at /vagrant/mysql-5.5.35/sql/sql_select.cc:1858
    #3  0x000000000062b2a0 in mysql_select (thd=0x37670e0, rref_pointer_array=0x3769400, tables=0x0, wild_num=0,
        fields=..., conds=0x0, og_num=0, order=0x0, group=0x0, having=0x0, proc_param=0x0, select_options=2147748608,
        result=0x7f350c001658, unit=0x3768bf8, select_lex=0x3769218) at /vagrant/mysql-5.5.35/sql/sql_select.cc:2604
    #4  0x00000000006232f5 in handle_select (thd=0x37670e0, lex=0x3768b48, result=0x7f350c001658,
        setup_tables_done_option=0) at /vagrant/mysql-5.5.35/sql/sql_select.cc:297
    #5  0x00000000005fe82d in execute_sqlcom_select (thd=0x37670e0, all_tables=0x0)
        at /vagrant/mysql-5.5.35/sql/sql_parse.cc:4627
    #6  0x00000000005f7379 in mysql_execute_command (thd=0x37670e0) at /vagrant/mysql-5.5.35/sql/sql_parse.cc:2178
    #7  0x0000000000600a43 in mysql_parse (thd=0x37670e0, rawbuf=0x7f350c001430 "SELECT UNIX_TIMESTAMP()", length=23,
        parser_state=0x7f35195056f0) at /vagrant/mysql-5.5.35/sql/sql_parse.cc:5664
    #8  0x00000000005f490a in dispatch_command (command=COM_QUERY, thd=0x37670e0,
        packet=0x3770e21 "SELECT UNIX_TIMESTAMP()", packet_length=23) at /vagrant/mysql-5.5.35/sql/sql_parse.cc:1040
    #9  0x00000000005f3c00 in do_command (thd=0x37670e0) at /vagrant/mysql-5.5.35/sql/sql_parse.cc:773
    #10 0x00000000006daa4b in do_handle_one_connection (thd_arg=0x37670e0)
        at /vagrant/mysql-5.5.35/sql/sql_connect.cc:862
    #11 0x00000000006da583 in handle_one_connection (arg=0x37670e0) at /vagrant/mysql-5.5.35/sql/sql_connect.cc:781
    #12 0x00007f352e043851 in start_thread () from /lib64/libpthread.so.0
    #13 0x00007f352cd9890d in clone () from /lib64/libc.so.6
```
    
.4. query读取数据结果

```
    #0  cli_read_query_result (mysql=0x7f3508004960) at /vagrant/mysql-5.5.35/sql-common/client.c:3829
    #1  0x0000000000738016 in mysql_real_query (mysql=0x7f3508004960, query=0xb80e34 "SELECT UNIX_TIMESTAMP()",
        length=23) at /vagrant/mysql-5.5.35/sql-common/client.c:3918
    #2  0x00000000005766ec in get_master_version_and_clock (mysql=0x7f3508004960, mi=0x375b400)
        at /vagrant/mysql-5.5.35/sql/slave.cc:1328
    #3  0x000000000057b35a in handle_slave_io (arg=0x375b400) at /vagrant/mysql-5.5.35/sql/slave.cc:2881
    #4  0x00007f352e043851 in start_thread () from /lib64/libpthread.so.0
    #5  0x00007f352cd9890d in clone () from /lib64/libc.so.6
```
    
.5. slave发送COM_BINLOG_DUMP

```
    #0  request_dump (thd=0x7f35f80008c0, mysql=0x7f35f80076c0, mi=0x3301ac0,
        suppress_warnings=0x7f361c189e2b)
        at /vagrant/mysql-5.5.35/sql/slave.cc:2184
    #1  0x000000000057b596 in handle_slave_io (arg=0x3301ac0)
        at /vagrant/mysql-5.5.35/sql/slave.cc:2935
    #2  0x00007f3620c66851 in start_thread () from /lib64/libpthread.so.0
    #3  0x00007f361f9bb90d in clone () from /lib64/libc.so.6
```