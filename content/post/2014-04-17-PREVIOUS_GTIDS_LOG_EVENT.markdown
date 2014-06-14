+++
draft = false
title = "PREVIOUS_GTIDS_LOG_EVENT的格式"
date = 2014-04-17T22:08:00Z
tags = [ "mysql", "binlog", "GTID"]
+++

并没找到特别好的对`PREVIOUS_GTIDS_LOG_EVENT`格式的描述, 自己写一个

据下面这个例子, 是`mysqlbinlog`的分析结果

```
# at 120
#140417 15:50:36 server id 904898000  end_log_pos 311 CRC32 0x311ec069
# Position  Timestamp   Type   Master ID        Size      Master Pos    Flags
#       78 cc 87 4f 53   23   d0 a5 ef 35   bf 00 00 00   37 01 00 00   00 00
#       8b 04 00 00 00 00 00 00 00  7e 23 40 1a c6 03 11 e3 |................|
#       9b 8e 13 5e 10 e6 a0 5c fb  01 00 00 00 00 00 00 00 |................|
#       ab 01 00 00 00 00 00 00 00  06 00 00 00 00 00 00 00 |................|
#       bb 81 86 fc 1e c5 ff 11 e3  8d f9 e6 6c cf 50 db 66 |...........l.P.f|
#       cb 01 00 00 00 00 00 00 00  01 00 00 00 00 00 00 00 |................|
#       db 0c 00 00 00 00 00 00 00  a6 ce 32 8c c6 02 11 e3 |..........2.....|
#       eb 8e 0d e6 6c cf 50 db 66  01 00 00 00 00 00 00 00 |...l.P.f........|
#       fb 01 00 00 00 00 00 00 00  07 00 00 00 00 00 00 00 |................|
#      10b b7 00 99 20 c6 01 11 e3  8e 07 5e 10 e6 a0 5c fb |................|
#      11b 01 00 00 00 00 00 00 00  01 00 00 00 00 00 00 00 |................|
#      12b 07 00 00 00 00 00 00 00  69 c0 1e 31             |........i..1|
#      Previous-GTIDs
# 7e23401a-c603-11e3-8e13-5e10e6a05cfb:1-5,
# 8186fc1e-c5ff-11e3-8df9-e66ccf50db66:1-11,
# a6ce328c-c602-11e3-8e0d-e66ccf50db66:1-6,
# b7009920-c601-11e3-8e07-5e10e6a05cfb:1-6
```

从78-8a的位置, 是Binlog Event header, 参看[这里](http://dev.mysql.com/doc/internals/en/binlog-event-header.html)

最后四个字节, (69 c0 1e 31) 是checksum, 与参数 [binlog-checksum](http://dev.mysql.com/doc/refman/5.6/en/replication-options-binary-log.html#option_mysqld_binlog-checksum) 有关

中间的部分, 是gtid的数据区, 格式如下:

层次 | 字节数 | 含义 | 例子中的数值
--- | --- | --- | ---
0 | 8 | GTID中sid-number的组数 | 例子中为四组
1 | 16 | 第一组sid-number的sid部分 | 例子中为(7e 23 40 1a c6 03 11 e3 9b 8e 13 5e 10 e6 a0 5c fb)
1 | 8 | 第一组sid-number中, internal numbers的个数 | 例子中为1个internal number (`1-5`)
2 | 8 | 第一组sid-number中, 第一个internal number的起始number | 例子中为`1`
2 | 8 | 第一组sid-number中, 第一个internal number的结束number+1 | 例子中为`5+1=6`
2 | 8 | 第一组sid-number中, 第二个internal number的起始number | ... (例子中没有第二个internal number)
2 | 8 | 第一组sid-number中, 第二个internal number的结束number+1 | ... (例子中没有第二个internal number)
... | ... | ... | ...
1 | 16 | 第二组sid-number的sid部分 | ...
... | ... | ... | ...