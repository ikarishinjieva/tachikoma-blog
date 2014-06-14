+++
draft = false
title = "lisp一个大写的坑"
date = 2013-04-16T23:12:00Z
tags = [ "lisp"]
+++

最近一直掉在一个坑里，今天刚出坑

想用宏定义不同的函数，类似于:

```
(defmacro macro (name)
	   `(defmethod ,(intern (format nil "set-~a" name)) ()))
```

跑(macro test)，结果就是

(函数名是"|set-TEST|"，而不是需要的"set-test")

```
#<STANDARD-METHOD |set-TEST| NIL>
```

几天的困惑以后（尝试换过lisp的实现去测试），找到了[这篇文章](http://www.cs.rochester.edu/~schubert/247-447/symbols-in-lisp.html)，发现是符号名大小写引起的问题

```
CL-USER> (eq (intern "test") 'test)
NIL
CL-USER> (intern "test")
|test|
:INTERNAL
CL-USER> (eq (intern "TEST") 'test)
T
CL-USER> (intern "TEST")
TEST
:INTERNAL
```

大小写通过intern生成的符号是不一样的，全大写才会生成正确的符号。

参考：

[How to handle symbols in LISP](http://www.cs.rochester.edu/~schubert/247-447/symbols-in-lisp.html)