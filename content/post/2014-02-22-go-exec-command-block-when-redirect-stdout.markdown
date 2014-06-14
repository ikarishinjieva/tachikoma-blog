+++
draft = false
title = "GO exec.command.Wait 执行后台程序,在重定向输出时卡住"
date = 2014-02-22T10:30:00Z
tags = [ "go", "bug"]
+++

在GO上发现以下现象

```
    c := exec.Command("sh", "-c", "sleep 100 &")
    var b bytes.Buffer
    c.Stdout = &b
    
    if e := c.Start(); nil != e {
        fmt.Printf("ERROR: %v\n", e)
    }
    if e := c.Wait(); nil != e {
        fmt.Printf("ERROR: %v\n", e)
    }
```
    
这个代码会一直等到`sleep 100`完成后才退出, 与常识不符.

但去掉Stdout重定向后, 代码就不会等待卡住

```
    c := exec.Command("sh", "-c", "sleep 100 &")
    if e := c.Start(); nil != e {
        fmt.Printf("ERROR: %v\n", e)
    }
    if e := c.Wait(); nil != e {
        fmt.Printf("ERROR: %v\n", e)
    }
```
    
在运行时打出stacktrace, 再翻翻GO的源代码, 发现GO卡在以下代码

```
    func (c *Cmd) Wait() error {
        ...
        state, err := c.Process.Wait()
        ...
        var copyError error
        for _ = range c.goroutine {
            if err := <-c.errch; err != nil && copyError == nil {
                copyError = err
            }
        }
        ...
    }
```

可以看到`Wait()`在等待Process结束后, 还等待了所有`c.goroutine`的`c.errch`信号. 参看以下代码:

```
    func (c *Cmd) stdout() (f *os.File, err error) {
        return c.writerDescriptor(c.Stdout)
    }
    
    func (c *Cmd) writerDescriptor(w io.Writer) (f *os.File, err error) {
        ...
        c.goroutine = append(c.goroutine, func() error {
            _, err := io.Copy(w, pr)
            return err
        })
        ...
    }
```

重定向`stdout`时, 会添加一个监听任务到`goroutine` (`stderr`也是同理)

结论是由于将`sleep 100`放到后台执行, 其进程`stdout`并没有关闭, `io.Copy()`不会返回, 所以会卡住

临时的解决方法就是将后台进程的`stdout`和`stderr`重定向出去, 以下代码不会卡住:

```
    c := exec.Command("sh", "-c", "sleep 100 >/dev/null 2>/dev/null &")
    var b bytes.Buffer
    c.Stdout = &b
    
    if e := c.Start(); nil != e {
        fmt.Printf("ERROR: %v\n", e)
    }
    if e := c.Wait(); nil != e {
        fmt.Printf("ERROR: %v\n", e)
    }
```

已经报了[bug](https://code.google.com/p/go/issues/detail?id=7378&thanks=7378&ts=1392967848)

但想不出好的GO代码的修改方案