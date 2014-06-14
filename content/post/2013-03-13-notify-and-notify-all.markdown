+++
draft = false
title = "Thread Notify 和 NotifyAll"
date = 2013-03-13T21:47:00Z
tags = [ "concurrency"]
+++


参考：[http://blog.csdn.net/iceman1952/article/details/2159812](http://blog.csdn.net/iceman1952/article/details/2159812)

```
public class Notify {
    private static class T extends Thread {
        public T(String s) {
            super(s);
        }

        @Override
        public void run() {
            System.out.println(String.format("%s run.", this.getName()));
            synchronized (Notify.class) {
                try {
                    Notify.class.wait();
                } catch (InterruptedException e) {
                    e.printStackTrace();
                }
            }
            System.out.println(String.format("%s done.", this.getName()));
        }
    }

    public static void main(String[] args) throws InterruptedException {
        new T("thread 1").start();
        new T("thread 2").start();
        Thread.sleep(1000);
        System.out.println("notify");
        synchronized (Notify.class) {
            Notify.class.notify();
            //Notify.class.notifyAll(); //alternative
        }
    }
}
```

Notify版本主线程是不会退出的，因为释放了一个wait，另一个就会等到天荒地老。

NotifyAll主线程会退出。