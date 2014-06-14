+++
draft = false
title = "golang, windows和linux上的文件锁"
date = 2014-03-20T22:43:00Z
tags = [ "go", "lock"]
+++

直接上代码, `LockFile`可以获得一个文件的独占权, 或阻塞等待

linux
---

```
    func LockFile(file *os.File) error {
    	return syscall.Flock(int(file.Fd()), syscall.LOCK_EX)
    }
```
    
windows
---

```
    func LockFile(file *os.File) error {
    	h, err := syscall.LoadLibrary("kernel32.dll")
    	if err != nil {
    		return err
    	}
    	defer syscall.FreeLibrary(h)
    
    	addr, err := syscall.GetProcAddress(h, "LockFile")
    	if err != nil {
    		return err
    	}
    	for {
    		r0, _, _ := syscall.Syscall6(addr, 5, file.Fd(), 0, 0, 0, 1, 0)
    		if 0 != int(r0) {
    			break
    		}
    		time.Sleep(100 * time.Millisecond)
    	}
    	return nil
    }
```