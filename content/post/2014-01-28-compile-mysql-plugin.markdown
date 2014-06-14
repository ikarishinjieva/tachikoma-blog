+++
draft = false
title = "编译mysql插件的碰到的问题"
date = 2014-01-28T16:48:00Z
tags = [ "mysql", "mysql plugin"]
+++

最近尝试制作了[一个mysql的插件](https://github.com/ikarishinjieva/mysql_plugin-binlog_dump_list). 对c/c++的编译不熟, 又是第一次尝试做mysql插件, 编译过程中碰到些状况

编写好mysql插件后, 编译成功, 在mysql中安装运行报错: 取了`threads`中的THD, 其中THD->thread_id值为空

由于是mysql内置的数据结构, 一时没了头绪, 只能通过gdb连上去看看

发现plugin打印出来的thread_id距离THD开头的距离为

    tmp=0x3661f80
    &tmp->thread_id=0x36637b0
    delta = 0x1830
    
而gdb打印出来的距离为
    
    (gdb) p tmp
    $1 = (THD *) 0x3661f80
    (gdb) p &tmp->thread_id
    $2 = (my_thread_id *) 0x3663878
    delta = 0x18F8
    
结论很显然, plugin编译的THD结构和mysqld的THD结构不匹配, 即plugin的编译参数和mysqld的编译参数不一样.

当然mysql的文档上只会说一句大意是 "**编译参数应当设置成一样的**"的话

其中比较重要的几个编译选项

1. DBUG_ON
2. SAFE_MUTEX
3. DBUG_OFF (不设置DBUG_ON并不等于DBUG_OFF)

这几个选项会影响当使用mysqld内部数据结构的长度, 不排除还有其他