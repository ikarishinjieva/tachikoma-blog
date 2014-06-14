+++
draft = false
title = "TProfiler的基本原理"
date = 2013-01-27T23:59:00Z
tags = [ "TProfiler", "javascript"]
+++

粗粗看了看taobao [TProfiler](https://github.com/taobao/TProfiler)的源码，原理有点意思，java代码的质量属于实习生级，也缺乏测试。

一些参考：

[Java SE 6 新特性: Instrumentation 新功能 by IBM](http://www.ibm.com/developerworks/cn/java/j-lo-jse61/index.html) <介绍了Java 5&6 instrument(更换类实现，类似于AOP)的用法，以及classpath的动态增补(这个很有用)>

[objectweb.asm user guide](http://download.forge.objectweb.org/asm/asm4-guide.pdf) <TProfiler用 objectweb.asm解析和编译class byte code>