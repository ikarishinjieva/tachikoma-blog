+++
draft = false
title = "CSS compressor bug"
date = 2013-02-04T21:49:00Z
tags = [ "css"]
+++

使用[css compressor](http://www.csscompressor.com/) 压缩项目中的css，可以合并相同定义的style，但也引起了bug。

比如：

.A的类型应当是background: BB

```
.A, .B {
        background: BB
}
 
.A {
        background: AA
}

//in another file
.A, .B {
        background: BB
}
```

压缩后，.A的类型变为background: AA

```
.A, .B {
        background: BB
}
 
.A {
        background: AA
}
```

因为合并了相同定义，覆盖关系被打乱。

暂时没找到好的css compressor，来分解并合并css