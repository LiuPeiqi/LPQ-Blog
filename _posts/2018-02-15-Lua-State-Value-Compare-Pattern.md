---
layout: post
title: "Lua中状态量的比较模式"
date: 2018-02-15
tags: lua string enum 性能benchmark  
---

学习lua快半年了，看了两个不同组里使用lua比较常量的习惯：
 1. 直接字符串比较，类似`state == 'OpenState'`这样的形式
 2. 在lua中构造一个类似枚举的全局变量table，类似`state == WINDOW_STATES.OPEN_STATE`，其中WINDOW_STATES是注册的全局table，state和OPEN_STATE是整数类型

从感觉上看，第一种方法方便、可读性好。而第二种似乎为了避免应为字符串比较带来的不必要多性能开销。

### 真的是这样么？
咋一看，好像是的，但是隐隐约约好像发现点什么问题：一般有GC托管的语言，字符串比较需要小心一些，因为对于对象来说`==`通常代表比较引用，如果要比较具体的值，需要特别地使用类似`equalTo`的类型方法。但是，lua里没有针对string类型的equal方法，那么lua里字符串的比较到底是比的什么呢？看reference manual！[lua 5.3.4，第3.4.4章](http://www.lua.org/manual/5.3/manual.html#3.4.4)
>Equality (==) first compares the type of its operands. If the types are different, then the result is false. Otherwise, the values of the operands are compared. Strings are compared in the obvious way. Numbers are equal if they denote the same mathematical value.

### Lua究竟怎么比较字符串
Obvious是个啥，先网络上搜索一番，比较多的说法是字符串比较是比较两个串的hash值，如果hash值一样，则两个串是一样的。如果真是这样，那么lua的字符串比较还是比较悲观的，因为hash的计算负担太重了。
请教组里的大神，大神说是比较引用值。因为lua维护一个全局唯一的字符串池，所以所有具有相同hash的（在parser阶段就确认的）字符串都是用同一个串的引用。
谁是对的呢？似乎最好的办法就是看lua源码了。然而我比较懒，在看源码之前，我们尝试一下看看能不能从表现上大致判断一下谁是正确的。
上面两种观点的本质区别是字符串的hash值是什么时机确认的。第一种观点认为字符串在比较发生时分别去计算hash值，第二种观点认为字符串的hash值是在parser阶段确认的，字符串的比较相当于引用（指针）比较。根据这一个本质的区别，不难设计实验：分别比较一系列较短的字符串和一系列较长的字符串，如果两次比较再时间的区别不大，则可以证明字符串的hash值不是在比较发生的时候计算的。反之相同的字符串可能有两种或以上的引用。

#### Benchmark: Round One
> 测试环境
lua: lua-5.3.4 64bit
Mac I5 3GHz, L2 Cache 256KB, L3 Cache 6MB
Memory 8G

先构造了一个生成测试用例的方法：随机生成n个指定长度的字符串，然后随机组合成m个比较语句，并统计true和false的个数。
```
load short string test case cost:	1.170549
FIRST CALL
count true:	988	false:	999012
Compare 1000000 times, 1000 strings, min_len:5, max_len:16, cost:0.027576s
SECOND CALL
count true:	988	false:	999012
Compare 1000000 times, 1000 strings, min_len:5, max_len:16, cost:0.025722s
load long string test case cost:	3.613766
FIRST CALL
count true:	963	false:	999037
Compare 1000000 times, 1000 strings, min_len:100, max_len:200, cost:0.028461s
SECOND CALL
count true:	963	false:	999037
Compare 1000000 times, 1000 strings, min_len:100, max_len:200, cost:0.024332999999999s
```
因为不论字符串的长短，比较时间是非常接近的，所以至少字符串的hash值不是每次都要计算的。

#### Benchmark: Round Two
如果字符串果真是按照引用来比较，那么字符串比较跟整数比较用时相差不大才对。那我们看看测试结果：
```
load numbers test case cost:	0.906
FIRST CALL
count true:	1024	false:	998976
Compare 1000000 times, 1000 numbers, cost:0.027763s
SECOND CALL
count true:	1024	false:	998976
Compare 1000000 times, 1000 numbers, cost:0.024379s
```
跟字符串的比较时间基本一致！

### 字符串的比较跟数字比较是一个量级的
光是上面的尝试还是存在一些小疑问的：
1. 测试案例中的所有字符串比较都是常量字符串直接比较，数字的比较也是常量比较，这种情况在生产环境中并不实用。
2. 测试用例中仅有一条语句是有效的比较用时，其他还有一些赋值与运算语句的时间会带来干扰。

这两个问题的验证方法也不难找出，修改一下测试用例依然满足字符串比较与数字比较在同一个量级里的结论。

### 枚举的比较
枚举的问题除了直观上不如字符串利于阅读，还一个是table作为一个hash结构，查表的复杂度虽然是O(1)，但是常量系数可不小。在看到了前面比较的结果后，不妨预测一下枚举的结果：除了等价的数值比较，还有一个就是查表的时间，所以总时间加起来还是相对比较长的。

#### Benchmark: Round Three
```
load short enum test case cost:	1.57917
FIRST CALL
count true:	1030	false:	998970
Compare 1000000 times, 100 enums, 10 items for each enum, key_min_len:5, key_max_len:16, cost:0.04339s
SECOND CALL
count true:	1030	false:	998970
Compare 1000000 times, 100 enums, 10 items for each enum, key_min_len:5, key_max_len:16, cost:0.039725000000001s
load long enum test case cost:	4.20531
FIRST CALL
count true:	504	false:	999496
Compare 1000000 times, 100 enums, 10 items for each enum, key_min_len:100, key_max_len:200, cost:0.084571s
SECOND CALL
count true:	504	false:	999496
Compare 1000000 times, 100 enums, 10 items for each enum, key_min_len:100, key_max_len:200, cost:0.047225000000001s
true
```

### 结论
看来在lua里，使用table模拟一个枚举的操作并没有带来性能的提升，反而即影响阅读又拖累性能。看来老生常谈的问题还是需要格外注意：在编码前期切勿过早的开始优化；在优化之前一定要测试好性能瓶颈，不能盲目优化。
