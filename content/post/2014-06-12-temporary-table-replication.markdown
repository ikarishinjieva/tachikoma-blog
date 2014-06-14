+++
draft = false
title = "测试Mysql临时表的复制"
date = 2014-06-12T22:32:00Z
tags = [ "mysql", "replication", "temporary table"]
+++

测试一下Mysql 5.6.17对临时表的复制

参考资料
---

1. Percona这篇08年的blog [Can MySQL temporary tables be made safe for statement-based replication?](http://www.mysqlperformanceblog.com/2008/05/26/mysql-temporary-tables-safe-for-statement-based-replication/), 是对于Mysql 5.1这方面的测试. 但根据对Mysql 5.6的相关测试, 其结论已经不适用. 其方法可供参考
2. Mysql Manual 对于临时表复制的[讨论](http://dev.mysql.com/doc/refman/5.6/en/replication-features-temptables.html), 其中一些重要的描述列在下面:

* Safe slave shutdown when using temporary tables
* By default, all temporary tables are replicated; this happens whether or not there are any matching `--replicate-do-db`, `--replicate-do-table`, or `--replicate-wild-do-table` options in effect
* the `--replicate-ignore-table` and `--replicate-wild-ignore-table` options are honored for temporary tables

概述
---

总共做了两个测试:

1. Mysql Manual中"Safe slave shutdown when using temporary tables"一节, 验证为何需要如此安全关闭slave
2. 验证在复制临时表时, master意外crash, 是否会造成slave上的资源泄露

每个测试后都有结论

测试一
---

针对Mysql Manual提到的"Safe slave shutdown when using temporary tables", 重现一下:

```
#准备环境, 断开复制
mysql-master> select @@binlog_format;
+-----------------+
| @@binlog_format |
+-----------------+
| MIXED           |
+-----------------+
1 row in set (0.02 sec)

mysql-slave> stop slave;
Query OK, 0 rows affected (0.03 sec)
```

```
#在master上构造使用临时表的两个transaction
mysql-master> flush logs;
Query OK, 0 rows affected (0.02 sec)

mysql-master> begin;
Query OK, 0 rows affected (0.00 sec)

mysql-master> create temporary table test.t(t int);
Query OK, 0 rows affected (0.01 sec)

mysql-master> commit;
Query OK, 0 rows affected (0.00 sec)

mysql-master> begin;
Query OK, 0 rows affected (0.00 sec)

mysql-master> insert into test.a select t from test.t;
Query OK, 0 rows affected (0.00 sec)
Records: 0  Duplicates: 0  Warnings: 0

mysql-master> commit;
Query OK, 0 rows affected (0.00 sec)
```

```
#查看master的binlog
mysql-master> show binlog events in "mysql-bin.000036" \G
*************************** 1. row ***************************
   Log_name: mysql-bin.000036
        Pos: 4
 Event_type: Format_desc
  Server_id: 1
End_log_pos: 120
       Info: Server ver: 5.6.17-debug-log, Binlog ver: 4
*************************** 2. row ***************************
   Log_name: mysql-bin.000036
        Pos: 120
 Event_type: Query
  Server_id: 1
End_log_pos: 195
       Info: BEGIN
*************************** 3. row ***************************
   Log_name: mysql-bin.000036
        Pos: 195
 Event_type: Query
  Server_id: 1
End_log_pos: 301
       Info: create temporary table test.t(t int)
*************************** 4. row ***************************
   Log_name: mysql-bin.000036
        Pos: 301
 Event_type: Query
  Server_id: 1
End_log_pos: 370
       Info: COMMIT
*************************** 5. row ***************************
   Log_name: mysql-bin.000036
        Pos: 370
 Event_type: Query
  Server_id: 1
End_log_pos: 445
       Info: BEGIN
*************************** 6. row ***************************
   Log_name: mysql-bin.000036
        Pos: 445
 Event_type: Query
  Server_id: 1
End_log_pos: 554
       Info: insert into test.a select t from test.t
*************************** 7. row ***************************
   Log_name: mysql-bin.000036
        Pos: 554
 Event_type: Query
  Server_id: 1
End_log_pos: 623
       Info: COMMIT
7 rows in set (0.00 sec)
```

```
#开启复制,让复制在两个transaction之间中断

mysql-slave> start slave until master_log_file='mysql-bin.000036', master_log_pos=370;
Query OK, 0 rows affected, 1 warning (0.02 sec)

mysql-slave> show slave status\G
*************************** 1. row ***************************
               Slave_IO_State: Waiting for master to send event
...
              Master_Log_File: mysql-bin.000036
          Read_Master_Log_Pos: 623
...
        Relay_Master_Log_File: mysql-bin.000036
             Slave_IO_Running: Yes
            Slave_SQL_Running: No
...
          Exec_Master_Log_Pos: 370
...
1 row in set (0.00 sec)

```

```
#查看slave正在使用的临时表, 并重启slave

mysql-slave> show status like '%temp%';                      
+------------------------+-------+
| Variable_name          | Value |
+------------------------+-------+
| Slave_open_temp_tables | 1     |
+------------------------+-------+
1 row in set (0.01 sec)

slave> service mysqld restart
```

```
#验证slave status


mysql-slave> show slave status\G
*************************** 1. row ***************************
...
              Master_Log_File: mysql-bin.000036
          Read_Master_Log_Pos: 623
...
        Relay_Master_Log_File: mysql-bin.000036
             Slave_IO_Running: Yes
            Slave_SQL_Running: No
...
                   Last_Errno: 1146
                   Last_Error: Error 'Table 'test.t' doesn't exist' on query. Default database: ''. Query: 'insert into test.a select t from test.t'
...
          Exec_Master_Log_Pos: 370
...
               Last_SQL_Errno: 1146
               Last_SQL_Error: Error 'Table 'test.t' doesn't exist' on query. Default database: ''. Query: 'insert into test.a select t from test.t'
  Replicate_Ignore_Server_Ids:
...
1 row in set (0.00 sec)

```

**结论**: 使用临时表时, slave并不保证crash-safe, 而且若在连续的transaction中复用同一个临时表, 完全没办法安全修复.


测试2
---

对于一个`create temporary table`, 已知`drop temporary table`会在session结束时写进binlog. 那么如果master意外退出, 是不是会对slave造成资源泄露? 比如不释放文件句柄

```
#准备master环境
mysql-master> select @@binlog_format;
+-----------------+
| @@binlog_format |
+-----------------+
| MIXED           |
+-----------------+
1 row in set (0.00 sec)

mysql-master> select @@gtid_mode;
+-------------+
| @@gtid_mode |
+-------------+
| OFF         |
+-------------+
1 row in set (0.00 sec)
```

```
#检查slave上的资源
mysql-slave> show status like '%open%';
+----------------------------+-------+
| Variable_name              | Value |
+----------------------------+-------+
...
| Innodb_num_open_files      | 6     |
| Open_files                 | 22    |
| Open_streams               | 0     |
| Open_table_definitions     | 70    |
| Open_tables                | 63    |
| Opened_files               | 164   |
| Opened_table_definitions   | 0     |
| Opened_tables              | 0     |
| Slave_open_temp_tables     | 0     |
...
+----------------------------+-------+
14 rows in set (0.00 sec)
```

```
#在master上创建5张临时表
mysql-master> create temporary table test.t1 (t int);create temporary table test.t2 (t int);create temporary table test.t3 (t int);create temporary table test.t4 (t int);create temporary table test.t5 (t int);
Query OK, 0 rows affected (0.02 sec)

Query OK, 0 rows affected (0.00 sec)

Query OK, 0 rows affected (0.01 sec)

Query OK, 0 rows affected (0.01 sec)

Query OK, 0 rows affected (0.01 sec)

```

```
#检查slave上的资源
mysql-slave> show status like '%open%';
+----------------------------+-------+
| Variable_name              | Value |
+----------------------------+-------+
...
| Innodb_num_open_files      | 11    |
| Open_files                 | 22    |
| Open_streams               | 0     |
| Open_table_definitions     | 70    |
| Open_tables                | 63    |
| Opened_files               | 179   |
| Opened_table_definitions   | 0     |
| Opened_tables              | 0     |
| Slave_open_temp_tables     | 5     |
...
+----------------------------+-------+
14 rows in set (0.00 sec)
```

```
#引发master故障, 重启master库
master> pkill -9 mysqld
master> /opt/mysql/bin/mysqld_safe &
```

```
#重启slave复制, 检查slave上的资源

mysql-slave> stop slave io_thread;
Query OK, 0 rows affected (0.02 sec)

mysql-slave> start slave io_thread;
Query OK, 0 rows affected (0.00 sec)

mysql-slave> show status like '%open%';
+----------------------------+-------+
| Variable_name              | Value |
+----------------------------+-------+
...
| Innodb_num_open_files      | 6     |
| Open_files                 | 22    |
| Open_streams               | 0     |
| Open_table_definitions     | 70    |
| Open_tables                | 63    |
| Opened_files               | 209   |
| Opened_table_definitions   | 0     |
| Opened_tables              | 0     |
| Slave_open_temp_tables     | 5     |
...
+----------------------------+-------+
14 rows in set (0.00 sec)
```

```
#在master上再次创建5张临时表, 检查slave上的资源
mysql-master> create temporary table test.t1 (t int);create temporary table test.t2 (t int);create temporary table test.t3 (t int);create temporary table test.t4 (t int);create temporary table test.t5 (t int);
Query OK, 0 rows affected (0.09 sec)

Query OK, 0 rows affected (0.00 sec)

Query OK, 0 rows affected (0.02 sec)

Query OK, 0 rows affected (0.00 sec)

Query OK, 0 rows affected (0.00 sec)


mysql-slave> show status like '%open%';
+----------------------------+-------+
| Variable_name              | Value |
+----------------------------+-------+
...
| Innodb_num_open_files      | 11    |
| Open_files                 | 22    |
| Open_streams               | 0     |
| Open_table_definitions     | 70    |
| Open_tables                | 63    |
| Opened_files               | 224   |
| Opened_table_definitions   | 0     |
| Opened_tables              | 0     |
| Slave_open_temp_tables     | 10    |
...
+----------------------------+-------+
```

**结论**: 复制临时表时,slave上消耗的资源, `Innodb_num_open_files`会及时回收,也就是说实际消耗的系统资源被及时回收. 但`Slave_open_temp_tables`会虚高不下,按照Mysql Manual中"Safe slave shutdown when using temporary tables"的叙述, 用`Slave_open_temp_tables`来判断关闭server的时机时, 会出现判断失误.
