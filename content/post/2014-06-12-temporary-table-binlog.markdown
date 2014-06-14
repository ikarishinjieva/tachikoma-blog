+++
draft = false
title = "测试Mysql临时表的binlog"
date = 2014-06-12T22:30:00Z
tags = [ "mysql", "binlog", "temporary table"]
+++

在Mysql 5.6.17上测试临时表生成的binlog

测试用例
---

|用例|row|statement|mixed|
|--------|--------|--------|--------|
|`create temporary table` 产生的binlog|1.1|1.2|1.3|
|`create temporary table` 产生的binlog (`mysqlbinlog`)|2.1|2.2|-|
|临时表对非临时表数据产生影响时, 产生的binlog|3.1|3.2|-|
|临时表对非临时表数据产生影响, 并rollback时, 产生的binlog|4.1|4.2|-|
|多session同时创建临时表, 产生的binlog|-|5.1|-|
|开启`enforce-gtid-consistency`时, `create temporary table`|-|6.1|-|


测试结论
---

.1. `create temporary table` 产生的binlog

结论: 可以看到`statement`和`mixed`模式生成的binlog一样. 而`row`模式中, 因为临时表并没有产生实际影响, 所以没有产生额外的binlog event


.2. `create temporary table` 产生的binlog (`mysqlbinlog`)

`show binlog events` 的输出只是摘要了binlog的内容, `mysqlbinlog`的输出才能精准的显示binlog的内容

重做`row`模式和`statement`模式的测试, 可以看到`row`模式虽然不产生`create temporary table`, 但是会产生一个`drop temporary table if exists`; `statement`模式产生`create temporary table`, 但不产生`drop temporary table`

.3. 临时表对非临时表数据产生影响时, 产生的binlog

可以看到`row`模式会产生非临时表的行日志.`statement`模式会严格记录语句.

.4. 临时表对非临时表数据产生影响,并rollback时, 产生的binlog

可以看到`row`模式下, rollback不会对binlog产生影响. 在`statement`模式下, 所有的语句都会如实反映在binlog里, 并进行rollback

.5. 多session同时创建临时表, 产生的binlog

不同于典型DDL, `create temporary table`记在transaction中.

由session结束产生的`drop temporary table`则类似于典型的DDL.

.6. 开启`enforce-gtid-consistency`时, `create temporary table`

开启`enforce-gtid-consistency`时, 在transaction内创建临时表会得到warning:

```
ERROR 1787 (HY000): When @@GLOBAL.ENFORCE_GTID_CONSISTENCY = 1, the statements CREATE TEMPORARY TABLE and DROP TEMPORARY TABLE can be executed in a non-transactional context only, and require that AUTOCOMMIT = 1.
```


---

元日志
---

.1.1

```
mysql> select @@gtid_mode;
+-------------+
| @@gtid_mode |
+-------------+
| OFF         |
+-------------+
1 row in set (0.00 sec)

mysql> set @@session.binlog_format="row";
Query OK, 0 rows affected (0.00 sec)

mysql> flush logs;
Query OK, 0 rows affected (0.00 sec)

mysql> begin;
Query OK, 0 rows affected (0.00 sec)

mysql> create temporary table test.t (t int);
Query OK, 0 rows affected (0.01 sec)

mysql> commit;
Query OK, 0 rows affected (0.00 sec)
```

```
mysql> show binlog events in 'mysql-bin.000014' \G
*************************** 1. row ***************************
   Log_name: mysql-bin.000014
        Pos: 4
 Event_type: Format_desc
  Server_id: 1
End_log_pos: 120
       Info: Server ver: 5.6.17-debug-log, Binlog ver: 4
```

.1.2

```
mysql> select @@gtid_mode;

+-------------+
| @@gtid_mode |
+-------------+
| OFF         |
+-------------+
1 row in set (0.00 sec)

mysql> set @@session.binlog_format="statement";
Query OK, 0 rows affected (0.00 sec)

mysql> flush logs;
Query OK, 0 rows affected (0.00 sec)

mysql> begin;
Query OK, 0 rows affected (0.00 sec)

mysql> create temporary table test.t (t int);
Query OK, 0 rows affected (0.01 sec)

mysql> commit;
Query OK, 0 rows affected (0.00 sec)
```


```
mysql> show binlog events in 'mysql-bin.000015' \G
*************************** 1. row ***************************
   Log_name: mysql-bin.000015
        Pos: 4
 Event_type: Format_desc
  Server_id: 1
End_log_pos: 120
       Info: Server ver: 5.6.17-debug-log, Binlog ver: 4
*************************** 2. row ***************************
   Log_name: mysql-bin.000015
        Pos: 120
 Event_type: Query
  Server_id: 1
End_log_pos: 195
       Info: BEGIN
*************************** 3. row ***************************
   Log_name: mysql-bin.000015
        Pos: 195
 Event_type: Query
  Server_id: 1
End_log_pos: 302
       Info: create temporary table test.t (t int)
*************************** 4. row ***************************
   Log_name: mysql-bin.000015
        Pos: 302
 Event_type: Query
  Server_id: 1
End_log_pos: 371
       Info: COMMIT
4 rows in set (0.00 sec)
```


.1.3

```
mysql> select @@gtid_mode;
+-------------+
| @@gtid_mode |
+-------------+
| OFF         |
+-------------+
1 row in set (0.01 sec)

mysql> select @@binlog_format;
+-----------------+
| @@binlog_format |
+-----------------+
| MIXED           |
+-----------------+
1 row in set (0.01 sec)

mysql> flush logs;
Query OK, 0 rows affected (0.02 sec)

mysql> begin;
Query OK, 0 rows affected (0.00 sec)

mysql> create temporary table test.t (t int);
Query OK, 0 rows affected (0.05 sec)

mysql> commit;
Query OK, 0 rows affected (0.00 sec)
```


```
mysql> show binlog events in 'mysql-bin.000011'\G
*************************** 1. row ***************************
   Log_name: mysql-bin.000011
        Pos: 4
 Event_type: Format_desc
  Server_id: 1
End_log_pos: 120
       Info: Server ver: 5.6.17-debug-log, Binlog ver: 4
*************************** 2. row ***************************
   Log_name: mysql-bin.000011
        Pos: 120
 Event_type: Query
  Server_id: 1
End_log_pos: 195
       Info: BEGIN
*************************** 3. row ***************************
   Log_name: mysql-bin.000011
        Pos: 195
 Event_type: Query
  Server_id: 1
End_log_pos: 302
       Info: create temporary table test.t (t int)
*************************** 4. row ***************************
   Log_name: mysql-bin.000011
        Pos: 302
 Event_type: Query
  Server_id: 1
End_log_pos: 371
       Info: COMMIT
```

.2.1

```
[root@localhost data]# /opt/mysql/bin/mysqlbinlog --base64-output=decode-rows mysql-bin.000014
/*!50530 SET @@SESSION.PSEUDO_SLAVE_MODE=1*/;
/*!40019 SET @@session.max_insert_delayed_threads=0*/;
/*!50003 SET @OLD_COMPLETION_TYPE=@@COMPLETION_TYPE,COMPLETION_TYPE=0*/;
DELIMITER /*!*/;
# at 4
#140612  4:38:58 server id 1  end_log_pos 120 CRC32 0xb935033a 	Start: binlog v 4, server v 5.6.17-debug-log created 140612  4:38:58
# at 120
#140612  4:42:30 server id 1  end_log_pos 257 CRC32 0x8f9ccf27 	Query	thread_id=2	exec_time=0	error_code=0
SET TIMESTAMP=1402548150/*!*/;
SET @@session.pseudo_thread_id=2/*!*/;
SET @@session.foreign_key_checks=1, @@session.sql_auto_is_null=0, @@session.unique_checks=1, @@session.autocommit=1/*!*/;
SET @@session.sql_mode=1075838976/*!*/;
SET @@session.auto_increment_increment=1, @@session.auto_increment_offset=1/*!*/;
/*!\C utf8 *//*!*/;
SET @@session.character_set_client=33,@@session.collation_connection=33,@@session.collation_server=33/*!*/;
SET @@session.lc_time_names=0/*!*/;
SET @@session.collation_database=DEFAULT/*!*/;
DROP TEMPORARY TABLE IF EXISTS `test`.`t` /* generated by server */
/*!*/;
# at 257
#140612  4:42:51 server id 1  end_log_pos 304 CRC32 0x62766a77 	Rotate to mysql-bin.000015  pos: 4
DELIMITER ;
# End of log file
ROLLBACK /* added by mysqlbinlog */;
/*!50003 SET COMPLETION_TYPE=@OLD_COMPLETION_TYPE*/;
/*!50530 SET @@SESSION.PSEUDO_SLAVE_MODE=0*/;
```

.2.2

```
[root@localhost data]# /opt/mysql/bin/mysqlbinlog --base64-output=decode-rows mysql-bin.000015
/*!50530 SET @@SESSION.PSEUDO_SLAVE_MODE=1*/;
/*!40019 SET @@session.max_insert_delayed_threads=0*/;
/*!50003 SET @OLD_COMPLETION_TYPE=@@COMPLETION_TYPE,COMPLETION_TYPE=0*/;
DELIMITER /*!*/;
# at 4
#140612  4:42:51 server id 1  end_log_pos 120 CRC32 0xc3707cb7 	Start: binlog v 4, server v 5.6.17-debug-log created 140612  4:42:51
# Warning: this binlog is either in use or was not closed properly.
# at 120
#140612  4:42:58 server id 1  end_log_pos 195 CRC32 0x2fd0ed95 	Query	thread_id=2	exec_time=0	error_code=0
SET TIMESTAMP=1402548178/*!*/;
SET @@session.pseudo_thread_id=2/*!*/;
SET @@session.foreign_key_checks=1, @@session.sql_auto_is_null=0, @@session.unique_checks=1, @@session.autocommit=1/*!*/;
SET @@session.sql_mode=1075838976/*!*/;
SET @@session.auto_increment_increment=1, @@session.auto_increment_offset=1/*!*/;
/*!\C utf8 *//*!*/;
SET @@session.character_set_client=33,@@session.collation_connection=33,@@session.collation_server=33/*!*/;
SET @@session.lc_time_names=0/*!*/;
SET @@session.collation_database=DEFAULT/*!*/;
BEGIN
/*!*/;
# at 195
#140612  4:42:58 server id 1  end_log_pos 302 CRC32 0xfc742b50 	Query	thread_id=2	exec_time=0	error_code=0
SET TIMESTAMP=1402548178/*!*/;
create temporary table test.t (t int)
/*!*/;
# at 302
#140612  4:43:00 server id 1  end_log_pos 371 CRC32 0x25648832 	Query	thread_id=2	exec_time=0	error_code=0
SET TIMESTAMP=1402548180/*!*/;
COMMIT
/*!*/;
DELIMITER ;
# End of log file
ROLLBACK /* added by mysqlbinlog */;
/*!50003 SET COMPLETION_TYPE=@OLD_COMPLETION_TYPE*/;
/*!50530 SET @@SESSION.PSEUDO_SLAVE_MODE=0*/;
```

.3.1 

```
mysql> select @@gtid_mode;
+-------------+
| @@gtid_mode |
+-------------+
| OFF         |
+-------------+
1 row in set (0.00 sec)

mysql> set @@session.binlog_format="row";
Query OK, 0 rows affected (0.00 sec)

mysql> flush logs;
Query OK, 0 rows affected (0.01 sec)

mysql> begin;
Query OK, 0 rows affected (0.00 sec)

mysql>  create temporary table test.t (t int);
Query OK, 0 rows affected (0.01 sec)

mysql> insert into test.t values(2);
Query OK, 1 row affected (0.00 sec)

mysql> insert into test.a select t from test.t;
Query OK, 1 row affected (0.00 sec)
Records: 1  Duplicates: 0  Warnings: 0

mysql> commit;
Query OK, 0 rows affected (0.01 sec)
```

```
[root@localhost data]# /opt/mysql/bin/mysqlbinlog --base64-output=decode-rows -v mysql-bin.000020
/*!50530 SET @@SESSION.PSEUDO_SLAVE_MODE=1*/;
/*!40019 SET @@session.max_insert_delayed_threads=0*/;
/*!50003 SET @OLD_COMPLETION_TYPE=@@COMPLETION_TYPE,COMPLETION_TYPE=0*/;
DELIMITER /*!*/;
# at 4
#140612  6:02:38 server id 1  end_log_pos 120 CRC32 0x31b6357c 	Start: binlog v 4, server v 5.6.17-debug-log created 140612  6:02:38
# Warning: this binlog is either in use or was not closed properly.
# at 120
#140612  6:02:53 server id 1  end_log_pos 188 CRC32 0x23bceabc 	Query	thread_id=6	exec_time=0	error_code=0
SET TIMESTAMP=1402552973/*!*/;
SET @@session.pseudo_thread_id=6/*!*/;
SET @@session.foreign_key_checks=1, @@session.sql_auto_is_null=0, @@session.unique_checks=1, @@session.autocommit=1/*!*/;
SET @@session.sql_mode=1075838976/*!*/;
SET @@session.auto_increment_increment=1, @@session.auto_increment_offset=1/*!*/;
/*!\C utf8 *//*!*/;
SET @@session.character_set_client=33,@@session.collation_connection=33,@@session.collation_server=33/*!*/;
SET @@session.lc_time_names=0/*!*/;
SET @@session.collation_database=DEFAULT/*!*/;
BEGIN
/*!*/;
# at 188
#140612  6:02:53 server id 1  end_log_pos 232 CRC32 0x1a87cc74 	Table_map: `test`.`a` mapped to number 70
# at 232
#140612  6:02:53 server id 1  end_log_pos 272 CRC32 0xf0c862fb 	Write_rows: table id 70 flags: STMT_END_F
### INSERT INTO `test`.`a`
### SET
###   @1=2
# at 272
#140612  6:02:55 server id 1  end_log_pos 303 CRC32 0xb2f66e82 	Xid = 92
COMMIT/*!*/;
DELIMITER ;
# End of log file
ROLLBACK /* added by mysqlbinlog */;
/*!50003 SET COMPLETION_TYPE=@OLD_COMPLETION_TYPE*/;
/*!50530 SET @@SESSION.PSEUDO_SLAVE_MODE=0*/;
```

.3.2

```
mysql> select @@gtid_mode;
+-------------+
| @@gtid_mode |
+-------------+
| OFF         |
+-------------+
1 row in set (0.00 sec)

mysql> set @@session.binlog_format="statement";
Query OK, 0 rows affected (0.00 sec)

mysql> flush logs;
Query OK, 0 rows affected (0.00 sec)

mysql> begin;
Query OK, 0 rows affected (0.00 sec)

mysql> create temporary table test.t (t int);
Query OK, 0 rows affected (0.01 sec)

mysql> insert into test.t values(3);
Query OK, 1 row affected (0.00 sec)

mysql> insert into test.a select t from test.t;
Query OK, 1 row affected (0.00 sec)
Records: 1  Duplicates: 0  Warnings: 0

mysql> commit;
Query OK, 0 rows affected (0.00 sec)
```

```
[root@localhost data]# /opt/mysql/bin/mysqlbinlog --base64-output=decode-rows mysql-bin.000021
/*!50530 SET @@SESSION.PSEUDO_SLAVE_MODE=1*/;
/*!40019 SET @@session.max_insert_delayed_threads=0*/;
/*!50003 SET @OLD_COMPLETION_TYPE=@@COMPLETION_TYPE,COMPLETION_TYPE=0*/;
DELIMITER /*!*/;
# at 4
#140612  6:07:43 server id 1  end_log_pos 120 CRC32 0xbcd985c3 	Start: binlog v 4, server v 5.6.17-debug-log created 140612  6:07:43
# Warning: this binlog is either in use or was not closed properly.
# at 120
#140612  6:07:50 server id 1  end_log_pos 195 CRC32 0xf5ea27f6 	Query	thread_id=7	exec_time=0	error_code=0
SET TIMESTAMP=1402553270/*!*/;
SET @@session.pseudo_thread_id=7/*!*/;
SET @@session.foreign_key_checks=1, @@session.sql_auto_is_null=0, @@session.unique_checks=1, @@session.autocommit=1/*!*/;
SET @@session.sql_mode=1075838976/*!*/;
SET @@session.auto_increment_increment=1, @@session.auto_increment_offset=1/*!*/;
/*!\C utf8 *//*!*/;
SET @@session.character_set_client=33,@@session.collation_connection=33,@@session.collation_server=33/*!*/;
SET @@session.lc_time_names=0/*!*/;
SET @@session.collation_database=DEFAULT/*!*/;
BEGIN
/*!*/;
# at 195
#140612  6:07:50 server id 1  end_log_pos 302 CRC32 0xa52fbe74 	Query	thread_id=7	exec_time=0	error_code=0
SET TIMESTAMP=1402553270/*!*/;
create temporary table test.t (t int)
/*!*/;
# at 302
#140612  6:07:55 server id 1  end_log_pos 400 CRC32 0x037b8754 	Query	thread_id=7	exec_time=0	error_code=0
SET TIMESTAMP=1402553275/*!*/;
insert into test.t values(3)
/*!*/;
# at 400
#140612  6:07:59 server id 1  end_log_pos 509 CRC32 0xa1dc2124 	Query	thread_id=7	exec_time=0	error_code=0
SET TIMESTAMP=1402553279/*!*/;
insert into test.a select t from test.t
/*!*/;
# at 509
#140612  6:08:01 server id 1  end_log_pos 540 CRC32 0xf7e3aa59 	Xid = 102
COMMIT/*!*/;
DELIMITER ;
# End of log file
ROLLBACK /* added by mysqlbinlog */;
/*!50003 SET COMPLETION_TYPE=@OLD_COMPLETION_TYPE*/;
/*!50530 SET @@SESSION.PSEUDO_SLAVE_MODE=0*/;
```

.4.1 

```
mysql> select @@gtid_mode;
+-------------+
| @@gtid_mode |
+-------------+
| OFF         |
+-------------+
1 row in set (0.00 sec)

mysql> set @@session.binlog_format="row";
Query OK, 0 rows affected (0.00 sec)

mysql> flush logs;
Query OK, 0 rows affected (0.00 sec)

mysql> begin;
Query OK, 0 rows affected (0.00 sec)

mysql> create temporary table test.t (t int);
Query OK, 0 rows affected (0.01 sec)

mysql> insert into test.t values(5);
Query OK, 1 row affected (0.01 sec)

mysql> insert into test.a select t from test.t;
Query OK, 1 row affected (0.00 sec)
Records: 1  Duplicates: 0  Warnings: 0

mysql> rollback;
Query OK, 0 rows affected, 1 warning (0.00 sec)

mysql> show warnings;
+---------+------+-----------------------------------------------------------------+
| Level   | Code | Message                                                         |
+---------+------+-----------------------------------------------------------------+
| Warning | 1751 | The creation of some temporary tables could not be rolled back. |
+---------+------+-----------------------------------------------------------------+
1 row in set (0.00 sec)
```

```
[root@localhost data]# /opt/mysql/bin/mysqlbinlog --base64-output=decode-rows mysql-bin.000024
/*!50530 SET @@SESSION.PSEUDO_SLAVE_MODE=1*/;
/*!40019 SET @@session.max_insert_delayed_threads=0*/;
/*!50003 SET @OLD_COMPLETION_TYPE=@@COMPLETION_TYPE,COMPLETION_TYPE=0*/;
DELIMITER /*!*/;
# at 4
#140612  6:25:58 server id 1  end_log_pos 120 CRC32 0x8f8f4247 	Start: binlog v 4, server v 5.6.17-debug-log created 140612  6:25:58
# Warning: this binlog is either in use or was not closed properly.
DELIMITER ;
# End of log file
ROLLBACK /* added by mysqlbinlog */;
/*!50003 SET COMPLETION_TYPE=@OLD_COMPLETION_TYPE*/;
/*!50530 SET @@SESSION.PSEUDO_SLAVE_MODE=0*/;
```

.4.2 

```
mysql> select @@gtid_mode;
+-------------+
| @@gtid_mode |
+-------------+
| OFF         |
+-------------+
1 row in set (0.00 sec)

mysql> set @@session.binlog_format="statement";
Query OK, 0 rows affected (0.00 sec)

mysql> flush logs;
Query OK, 0 rows affected (0.01 sec)

mysql> begin;
Query OK, 0 rows affected (0.00 sec)

mysql> create temporary table test.t (t int);
Query OK, 0 rows affected (0.01 sec)

mysql> insert into test.t values(4);
Query OK, 1 row affected (0.00 sec)

mysql> insert into test.a select t from test.t;
Query OK, 1 row affected (0.00 sec)
Records: 1  Duplicates: 0  Warnings: 0

mysql> rollback;
Query OK, 0 rows affected, 1 warning (0.00 sec)

mysql> show warnings;
+---------+------+-----------------------------------------------------------------+
| Level   | Code | Message                                                         |
+---------+------+-----------------------------------------------------------------+
| Warning | 1751 | The creation of some temporary tables could not be rolled back. |
+---------+------+-----------------------------------------------------------------+
1 row in set (0.00 sec)
```

```
[root@localhost data]# /opt/mysql/bin/mysqlbinlog --base64-output=decode-rows mysql-bin.000023
/*!50530 SET @@SESSION.PSEUDO_SLAVE_MODE=1*/;
/*!40019 SET @@session.max_insert_delayed_threads=0*/;
/*!50003 SET @OLD_COMPLETION_TYPE=@@COMPLETION_TYPE,COMPLETION_TYPE=0*/;
DELIMITER /*!*/;
# at 4
#140612  6:22:03 server id 1  end_log_pos 120 CRC32 0x8ebd7db6 	Start: binlog v 4, server v 5.6.17-debug-log created 140612  6:22:03
# Warning: this binlog is either in use or was not closed properly.
# at 120
#140612  6:22:13 server id 1  end_log_pos 195 CRC32 0x2ef37ea7 	Query	thread_id=9	exec_time=0	error_code=0
SET TIMESTAMP=1402554133/*!*/;
SET @@session.pseudo_thread_id=9/*!*/;
SET @@session.foreign_key_checks=1, @@session.sql_auto_is_null=0, @@session.unique_checks=1, @@session.autocommit=1/*!*/;
SET @@session.sql_mode=1075838976/*!*/;
SET @@session.auto_increment_increment=1, @@session.auto_increment_offset=1/*!*/;
/*!\C utf8 *//*!*/;
SET @@session.character_set_client=33,@@session.collation_connection=33,@@session.collation_server=33/*!*/;
SET @@session.lc_time_names=0/*!*/;
SET @@session.collation_database=DEFAULT/*!*/;
BEGIN
/*!*/;
# at 195
#140612  6:22:13 server id 1  end_log_pos 302 CRC32 0xc642d4a1 	Query	thread_id=9	exec_time=0	error_code=0
SET TIMESTAMP=1402554133/*!*/;
create temporary table test.t (t int)
/*!*/;
# at 302
#140612  6:22:17 server id 1  end_log_pos 400 CRC32 0x076861c4 	Query	thread_id=9	exec_time=0	error_code=0
SET TIMESTAMP=1402554137/*!*/;
insert into test.t values(4)
/*!*/;
# at 400
#140612  6:22:21 server id 1  end_log_pos 509 CRC32 0x2e43db50 	Query	thread_id=9	exec_time=0	error_code=0
SET TIMESTAMP=1402554141/*!*/;
insert into test.a select t from test.t
/*!*/;
# at 509
#140612  6:22:24 server id 1  end_log_pos 580 CRC32 0xdefa8f3d 	Query	thread_id=9	exec_time=0	error_code=0
SET TIMESTAMP=1402554144/*!*/;
ROLLBACK
/*!*/;
DELIMITER ;
# End of log file
ROLLBACK /* added by mysqlbinlog */;
/*!50003 SET COMPLETION_TYPE=@OLD_COMPLETION_TYPE*/;
/*!50530 SET @@SESSION.PSEUDO_SLAVE_MODE=0*/;
```

.5.1 

```
mysql-session1> set @@session.binlog_format="statement";
Query OK, 0 rows affected (0.00 sec)

mysql-session2> set @@session.binlog_format="statement";
Query OK, 0 rows affected (0.00 sec)

mysql-session1> flush logs;
Query OK, 0 rows affected (0.00 sec)

mysql-session1> begin;
Query OK, 0 rows affected (0.00 sec)

mysql-session1> create temporary table test.t(t int);
Query OK, 0 rows affected (0.01 sec)

mysql-session2> begin;
Query OK, 0 rows affected (0.00 sec)

mysql-session2> create temporary table test.t(t int);
Query OK, 0 rows affected (0.02 sec)

mysql-session1> commit;
Query OK, 0 rows affected (0.00 sec)

mysql-session2> commit;
Query OK, 0 rows affected (0.00 sec)

mysql-session1> exit;
Bye

mysql-session2> exit;
Bye
```

```

[root@localhost data]# /opt/mysql/bin/mysqlbinlog --base64-output=decode-rows mysql-bin.000028
/*!50530 SET @@SESSION.PSEUDO_SLAVE_MODE=1*/;
/*!40019 SET @@session.max_insert_delayed_threads=0*/;
/*!50003 SET @OLD_COMPLETION_TYPE=@@COMPLETION_TYPE,COMPLETION_TYPE=0*/;
DELIMITER /*!*/;
# at 4
#140612  6:45:24 server id 1  end_log_pos 120 CRC32 0x0ad8e5a0 	Start: binlog v 4, server v 5.6.17-debug-log created 140612  6:45:24
# Warning: this binlog is either in use or was not closed properly.
# at 120
#140612  6:45:58 server id 1  end_log_pos 195 CRC32 0x59b581d0 	Query	thread_id=14	exec_time=0	error_code=0
SET TIMESTAMP=1402555558/*!*/;
SET @@session.pseudo_thread_id=14/*!*/;
SET @@session.foreign_key_checks=1, @@session.sql_auto_is_null=0, @@session.unique_checks=1, @@session.autocommit=1/*!*/;
SET @@session.sql_mode=1075838976/*!*/;
SET @@session.auto_increment_increment=1, @@session.auto_increment_offset=1/*!*/;
/*!\C utf8 *//*!*/;
SET @@session.character_set_client=33,@@session.collation_connection=33,@@session.collation_server=33/*!*/;
SET @@session.lc_time_names=0/*!*/;
SET @@session.collation_database=DEFAULT/*!*/;
BEGIN
/*!*/;
# at 195
#140612  6:45:58 server id 1  end_log_pos 301 CRC32 0x274004b9 	Query	thread_id=14	exec_time=0	error_code=0
SET TIMESTAMP=1402555558/*!*/;
create temporary table test.t(t int)
/*!*/;
# at 301
#140612  6:46:54 server id 1  end_log_pos 370 CRC32 0x9f2ca921 	Query	thread_id=14	exec_time=0	error_code=0
SET TIMESTAMP=1402555614/*!*/;
COMMIT
/*!*/;
# at 370
#140612  6:46:17 server id 1  end_log_pos 445 CRC32 0x3f1094c3 	Query	thread_id=16	exec_time=0	error_code=0
SET TIMESTAMP=1402555577/*!*/;
SET @@session.pseudo_thread_id=16/*!*/;
BEGIN
/*!*/;
# at 445
#140612  6:46:17 server id 1  end_log_pos 551 CRC32 0x754cae85 	Query	thread_id=16	exec_time=0	error_code=0
SET TIMESTAMP=1402555577/*!*/;
create temporary table test.t(t int)
/*!*/;
# at 551
#140612  6:46:58 server id 1  end_log_pos 620 CRC32 0x73eb6f5a 	Query	thread_id=16	exec_time=0	error_code=0
SET TIMESTAMP=1402555618/*!*/;
COMMIT
/*!*/;
# at 620
#140612  6:47:22 server id 1  end_log_pos 733 CRC32 0xb4c3b1c0 	Query	thread_id=14	exec_time=0	error_code=0
use `test`/*!*/;
SET TIMESTAMP=1402555642/*!*/;
SET @@session.pseudo_thread_id=14/*!*/;
DROP /*!40005 TEMPORARY */ TABLE IF EXISTS `t`
/*!*/;
# at 733
#140612  6:47:38 server id 1  end_log_pos 846 CRC32 0x1287fb24 	Query	thread_id=16	exec_time=0	error_code=0
SET TIMESTAMP=1402555658/*!*/;
SET @@session.pseudo_thread_id=16/*!*/;
DROP /*!40005 TEMPORARY */ TABLE IF EXISTS `t`
/*!*/;
DELIMITER ;
# End of log file
ROLLBACK /* added by mysqlbinlog */;
/*!50003 SET COMPLETION_TYPE=@OLD_COMPLETION_TYPE*/;
/*!50530 SET @@SESSION.PSEUDO_SLAVE_MODE=0*/;
```

.6.1

```
mysql> select @@GTID_MODE;
+-------------+
| @@GTID_MODE |
+-------------+
| ON          |
+-------------+
1 row in set (0.00 sec)

mysql> select @@enforce_gtid_consistency;
+----------------------------+
| @@enforce_gtid_consistency |
+----------------------------+
|                          1 |
+----------------------------+
1 row in set (0.00 sec)

mysql> begin;
Query OK, 0 rows affected (0.00 sec)

mysql> create temporary table test.t(t int);
ERROR 1787 (HY000): When @@GLOBAL.ENFORCE_GTID_CONSISTENCY = 1, the statements CREATE TEMPORARY TABLE and DROP TEMPORARY TABLE can be executed in a non-transactional context only, and require that AUTOCOMMIT = 1.
```