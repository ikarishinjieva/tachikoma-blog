+++
draft = false
title = "读写锁-读可重入"
date = 2013-03-14T21:37:00Z
tags = [ "concurrency", "reentrant", "read-write-lock"]
+++

发现[这篇文献](http://tutorials.jenkov.com/java-concurrency/read-write-locks.html)描写读写锁和可重入性非常具体。

尝试实现文章中的读可重入的读写锁：

考虑如何测试一个读可重入的读写锁, 由于读写锁的性质(可以同时存在多个读锁), 如果只是在线程A连续申请两个读锁, 就无法证明是锁的重入性发挥了作用。

测试思路是先在线程A申请读锁, 然后在线程B申请写锁, 若在线程C申请读锁, 此读锁应阻塞。而如果在线程A申请另一个读锁(前一个未释放), 线程A不应被阻塞。

测试代码(我的确用了Main来测试...)

```
public static void main(String[] args) throws InterruptedException {
	final ReadWriteLockReadReentrant lock = new ReadWriteLockReadReentrant();

	new Thread() {
		@Override
		public void run() {
			try {
				lock.lockRead();
				System.out.println("Reading");
				sleep(5000);
				System.out.println("Inner Reading");
				lock.lockRead();
			} catch (InterruptedException e) {

			} finally {
				System.out.println("Inner Reading End");
				lock.unlockRead();
				System.out.println("Reading End");
				lock.unlockRead();
			}
		}
	}.start();
	Thread.sleep(500);
	
	new Thread() {
		@Override
		public void run() {
			try {
				System.out.println("Request write lock");
				lock.lockWrite();
				System.out.println("Writing");
			} catch (InterruptedException e) {

			} finally {
				System.out.println("Writing End");
				lock.unlockWrite();
			}
		}
	}.start();
}
```

结果应当是：Reading(线程A),Request write lock(线程B),Inner Reading(未阻塞),Inner Reading End,Reading End,Writing,Writing End

读重入的读写锁(基本是抄上面文献的代码~)

```
import java.util.HashMap;
import java.util.Map;

public class ReadWriteLockReadReentrant {
    private boolean hasWriter = false;
    private int writeRequests = 0;
    private Map<Thread, Integer> readers = new HashMap<Thread, Integer>();

    public synchronized void lockRead() throws InterruptedException {
        Thread current = Thread.currentThread();
        while (!couldRead(current)) {
            wait();
        }
        readers.put(current, getReaders(current) + 1);
    }

    private int getReaders(Thread current) {
        if (!readers.containsKey(current)) {
            return 0;
        }
        return readers.get(current);
    }

    private boolean couldRead(Thread current) {
        if (hasWriter) {
            return false;
        }
        if (readers.containsKey(current)) {
            return true; //important
        }
        if (writeRequests > 0) {
            return false;
        }
        return true;
    }

    public synchronized void unlockRead() {
        Thread current = Thread.currentThread();
        setReaders(current, getReaders(current) - 1);
        notifyAll();
    }

    private void setReaders(Thread current, Integer now) {
        if (now == 0) {
            readers.remove(current);
        } else {
            readers.put(current, now);
        }
    }

    public synchronized void lockWrite() throws InterruptedException {
        writeRequests++;
        while (readers.size() > 0) {
            wait();
        }
        writeRequests--;
        hasWriter = true;
    }


    public synchronized void unlockWrite() {
        hasWriter = false;
        notifyAll();
    }
}
```

需要注意的是标记"//important"的那行，如果这个判断和writeRequest的判断互换位置，线程B申请写锁被阻塞时，线程A无法申请到第二个读锁。一切就悲剧了。

标记为"//important"的判断和writeRequest的判断互换位置

```
private boolean couldRead(Thread current) {
	if (hasWriter) {
		return false;
	}
	if (writeRequests > 0) {
		return false;
	}
	if (readers.containsKey(current)) {
		return true; //important
	}
	return true;
}
```