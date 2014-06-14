+++
draft = false
title = "org.ow2.asm 通过类.class产生asm java代码"
date = 2013-01-29T23:00:00Z
tags = [ "java", "org.ow2.asm"]
+++

尝试给[TProfiler](https://github.com/taobao/TProfiler)写一些单元测试。难点是如何对byte code injection产生测试夹具。理想的状况是产生一些class byte code，通过transformer，将生成的class载入并测试行为。第一步产生class byte code的代码可以通过asm提供的工具生成:

```
java -classpath asm-all-4.1.jar org.objectweb.asm.util.ASMifier org/domain/package/YourClass.class
```

一些参考：
[ASM的FAQ](http://asm.ow2.org/doc/faq.html)，里面的干货很多