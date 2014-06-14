+++
draft = false
title = "可重入Lock"
date = 2013-03-13T23:01:00Z
tags = [ "concurrency"]
+++

参考：[Java并发编程实践](http://book.douban.com/subject/10484692/)

参考书里2.3.2对锁的重入性一句话搞定：“获取所得粒度是"线程"，而不是"调用"”

下面的代码验证内置锁(synchronize)和Lock(ReentrantLock)的重入性

内置锁可重入

```
public class Reentrant {
    public void method1() {
        synchronized (Reentrant.class) {
            System.out.println("method1 run");
            method2();
        }
    }

    public void method2() {
        synchronized (Reentrant.class) {
            System.out.println("method2 run in method1");
        }
    }

    public static void main(String[] args) {
        new Reentrant().method1();
    }
}
```

Lock对象可重入

```
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReentrantLock;

public class Reentrant2 {
    private Lock lock = new ReentrantLock();

    public void method1() {
        lock.lock();
        try {
            System.out.println("method1 run");
            method2();
        } finally {
            lock.unlock();
        }
    }

    public void method2() {
        lock.lock();
        try {
            System.out.println("method2 run in method1");
        } finally {
            lock.unlock();
        }
    }

    public static void main(String[] args) {
        new Reentrant2().method1();
    }
}
```

在同一线程里，method1调用持同样锁的method2，不会等锁。这就是锁的"重入"。

不同线程里锁不可重入

```
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReentrantLock;

public class Reentrant3 {
    private static Lock lock = new ReentrantLock();

    private static class T1 extends Thread {
        @Override
        public void run() {
            System.out.println("Thread 1 start");
            lock.lock();
            try {
                Thread.sleep(10000);
            } catch (InterruptedException e) {
                e.printStackTrace();
            } finally {
                lock.unlock();
            }
            System.out.println("Thread 1 end");
        }
    }

    private static class T2 extends Thread {
        @Override
        public void run() {
            System.out.println("Thread 2 start");
            lock.lock();
            lock.unlock();
            System.out.println("Thread 2 end");
        }
    }


    public static void main(String[] args) {
        new T1().start();
		Thread.sleep(100);
        new T2().start();
    }
}
```

不同线程可以看到T2一定会等到T1释放锁之后。
