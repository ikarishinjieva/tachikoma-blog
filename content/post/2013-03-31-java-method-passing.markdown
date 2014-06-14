+++
draft = false
title = "我写了半辈子程序 & java的重载方法选择基于编译期参数类型"
date = 2013-03-31T23:22:00Z
tags = [ "java"]
+++

一段时间没更新过blog,因为花了些时间在读lisp的入门,还将继续一段时间

先庆祝下自己25岁,可以正式对外宣称"我写了半辈子程序"

读lisp的入门时,有一个java的对比例子觉得很有意思(虽然事后想想也就那么回事)...

简单的说,一个call传递给object(根据运行时的类型找到需要处理这个call的类),并找到对应的方法(根据call参数的编译时类型,找到需要处理这个call的函数),并执行

```
public class A {
    public void foo(A a) {
        System.out.println("A/A");
    }

    public void foo(B b) {
        System.out.println("A/B");
    }
}

public class B extends A {
    public void foo(A a) {
        System.out.println("B/A");
    }

    public void foo(B b) {
        System.out.println("B/B");
    }
}

public class C {
    public static void main(String[] params) {
//        A obj = new A();
        A obj = new B();
        obj.foo(obj);
    }
}
```

运行结果是"B/A",B这个类是根据运行类型找到的,foo(A)这个方法是根据编译类型找到的。