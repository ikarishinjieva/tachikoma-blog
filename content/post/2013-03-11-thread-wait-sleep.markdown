+++
draft = false
title = "Thread wait 和 sleep"
date = 2013-03-11T22:32:00Z
tags = [ "concurrency", "workspace"]
+++

ifeve上发现几个多线程的[基础问题](http://ifeve.com/javaconcurrency-interview-questions-base/)。我一直不写多线程（我这两年到底都写了些什么~），重头学起。

sleep和wait的区别。sleep让出cpu，等一段时间，重新进入竞争，不释放锁。wait等一个状态notify，才重新进入竞争，但释放锁。

下面代码说明是否释放锁的区别：

sleep不会释放锁

```
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

public class MultiThread {
    public static class T1 extends Thread {
        @Override
        public void run() {
            synchronized (MultiThread.class) {
                System.out.println("T1 run");
                System.out.println("T1 sleep");
                try {
                    sleep(10000);
                } catch (InterruptedException e) {
                    throw new RuntimeException(e);
                }
                System.out.println("T1 wake up");
            }
        }
    }
    
    public static class T2 extends Thread {
        @Override
        public void run() {
            synchronized (MultiThread.class) {
                System.out.println("T2 run");
            }
        }
    }

    public static void main(final String[] args) throws InterruptedException {
        ExecutorService executorService = Executors.newFixedThreadPool(2);
        executorService.execute(new T1());
        Thread.sleep(1000);
        executorService.execute(new T2());
		
		//dispose
        executorService.awaitTermination(1, TimeUnit.HOURS);
    }
}
```

wait会释放锁

```
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

public class MultiThread2 {
    public static class T1 extends Thread {
        @Override
        public void run() {
            synchronized (MultiThread2.class) {
                System.out.println("T1 run");
                System.out.println("T1 wait");
                try {
                    MultiThread2.class.wait();
                } catch (InterruptedException e) {
                    throw new RuntimeException(e);
                }
                System.out.println("T1 wake up");
            }
        }
    }
    
    public static class T2 extends Thread {
        @Override
        public void run() {
            synchronized (MultiThread2.class) {
                System.out.println("T2 run");
            }
        }
    }

    public static void main(final String[] args) throws InterruptedException {
        ExecutorService executorService = Executors.newFixedThreadPool(2);
        executorService.execute(new T1());
        Thread.sleep(1000);
        executorService.execute(new T2());
		
		//dispose
        Thread.sleep(10000);
        synchronized (MultiThread2.class) {
            MultiThread2.class.notify();
        }
        executorService.awaitTermination(1, TimeUnit.HOURS);
    }
}
```

sleep的执行结果是T1 run, T1 sleep, T1 wake up, T2 run

wait的执行结果是T1 run, T1 wait, T2 run (此处锁被释放, T2获得锁), T1 wake up