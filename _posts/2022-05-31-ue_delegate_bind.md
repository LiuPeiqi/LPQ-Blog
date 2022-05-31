---
layout: post
title: "UE Delegate Bind的冗余复制问题"
data: 2022-05-31
tags: UE C++ Banchmark
excerpt_separator: <!--more-->
---

起因是发现动画实例在初始化时，创建和绑定本地委托太多，导致耗时太久。

<!--more-->

查看TDelegate的Bind函数源码，忽略模板信息：

```
void BindLambda(FunctorType&& InFunctor){
    *this = CreateLambda(InFunctor);
}

static TDelegate CreateLambda(FunctorType&& InFunctor){
    TDelegate Result;
    TBaseFunctorDelegateInstance::Create(Result, InFunctor);
    return Result;
}
```

拷贝构造函数和赋值函数同时调用，产生了一些冗余浪费。似乎Bind过程中的赋值操作没上面必要，如果把Bind函数直接改成Create方法，就能减少复制和赋值函数调用。

```
void BindLambda(FunctorType&& InFunctor){
    TBaseFunctorDelegateInstance::Create(*this, InFunctor);
}
```

BindLambda函数统计
|测试|耗时|调用次数|
| :-: | :-: | :-: |
|修改前|0.188ms|190p|
|修改后|0.099ms|190p|

看起来问题解决了，但实际这一行代码执行了怎样的一个过程呢？

### 具体发生了什么

UE Delegate的源码非常复杂，便于理解，我们分三个层次理解：

1. 最外层的模板封装，它对外提供统一兼容Lambda、函数指针、UFunction、UObject等类型的绑定和分发操作的接口。
1. 标定和判断是否是同一个委托的ID，以及可以提前绑定的函数参数。
1. 开辟和析构的空间分配器。

这里做一个简化模拟，暂不考虑模板、空间分配器和参数提前绑定的逻辑。


委托ID实现，用以判断是否是同一委托。UE的实现中ID是原子变量，线程安全但耗费大。

```
class FDelegateHandle {
public:
  enum GenerateNewHandle { New };
  FDelegateHandle(GenerateNewHandle) {
    static long id = 0;
    ID = ++id;
    std::cout << "FDelegateHandle(GenerateNewHandle):ID(" << ID
              << ") by:" << this << std::endl;
  }
  FDelegateHandle() : ID(0) {
    std::cout << "Empty FDelegateHandle():ID(" << ID << ") by:" << this
              << std::endl;
  }
  long long ID;
};
```

UE原版中用来提供ID和参数绑定的公共基类。这里删除了参数绑定相关功能，并主动实现了复制构造函数，来监控打印实例复制过程。

```
class TCommonDelegateInstance {
public:
  explicit TCommonDelegateInstance()
      : Handle(FDelegateHandle::GenerateNewHandle::New) {
    std::cout << " TCommonDelegateInstance() by:" << this << std::endl;
  }

  TCommonDelegateInstance(TCommonDelegateInstance &other) {
    std::cout
        << "default copy TCommonDelegateInstance(TCommonDelegateInstance&other) by:"
        << this << std::endl;
    Handle.ID = other.Handle.ID;
  }

  FDelegateHandle Handle;
};
```

UE中用来实现各个类型绑定的实现类，这里只摘取了Lambda对应的类作为分析。而且原版Delegate的空间分配是通过默认的分配器管理的，并且使用placement new操作符主动调用相应构造函数。这里调用简化版的默认构造会导致多执行函数，后面涉及到时会指出。

```
class TFunctionDelegateInstance : public TCommonDelegateInstance {
public:
  TFunctionDelegateInstance(const void *InFunctor)
      : TCommonDelegateInstance(), Functor(InFunctor) {
    std::cout << "TFunctionDelegateInstance(const void *InFunctor) by:" << this
              << " InFunctor:" << InFunctor << std::endl;
  }

  TFunctionDelegateInstance() : Functor(nullptr) {
    std::cout << "Alloc TFunctionDelegateInstance() by:" << this << std::endl;
  }

  TFunctionDelegateInstance(TFunctionDelegateInstance &Other)
      : TCommonDelegateInstance(Other) {
    std::cout << "default copy TFunctionDelegateInstance(TFunctionDelegateInstance& "
                 "other)  by:"
              << this << std::endl;
    this->Functor = Other.Functor;
  }

  void CreateCopy(TFunctionDelegateInstance *&Base) {
    std::cout << "CreateCopy(TCommonDelegateInstance &Base) by:" << Base
              << std::endl;
    Base = new TFunctionDelegateInstance();
    new (Base) TFunctionDelegateInstance(*this);
  }

  static void Create(TFunctionDelegateInstance *&Base, const void *InFunctor) {
    std::cout
        << "Create(TFunctionDelegateInstance &Base, const void *InFunctor) by:"
        << Base << std::endl;
    Base = new TFunctionDelegateInstance();
    new (Base) TFunctionDelegateInstance(InFunctor);
  }

protected:
  const void *Functor;
};
```

最终对外封装的委托类型，无参构造函数在原版中几乎无行为。

```
class TDelegate {
public:
  ~TDelegate() { std::cout << "~TDelegate() by:" << this << std::endl; }
  TDelegate() { std::cout << "Empty TDelegate() by:" << this << std::endl; }
  TDelegate(TDelegate &&Other) {
    std::cout << "TDelegate(TDelegate&& Other) by:" << this << std::endl;
    *this = std::move(Other);
  }
  TDelegate(const TDelegate &Other) {
    std::cout << "TDelegate(const TDelegate& Other) by:" << this << std::endl;
    *this = Other;
  }
  TDelegate &operator=(TDelegate &&Other) {
    Other.Instance->CreateCopy(this->Instance);
    std::cout << "operator =(TDelegate&& Other) by:" << this;
    if (this->Instance) {
      std::cout << " ID:" << this->Instance->Handle.ID;
    }
    std::cout << std::endl;
    return *this;
  }
  TDelegate &operator=(const TDelegate &Other) {
    Other.Instance->CreateCopy(this->Instance);
    std::cout << "operator =(const TDelegate& Other) by:" << this;
    if (this->Instance) {
      std::cout << " ID:" << this->Instance->Handle.ID;
    }
    std::cout << std::endl;
    return *this;
  }

  void Bind(void *InFunctor) {
    std::cout << "TDelegate::Bind by:" << this << std::endl;
    *this = Create(InFunctor);
  }

  static TDelegate Create(void *InFunctor) {
    TDelegate result;
    std::cout << "TDelegate::Create by:" << &result << std::endl;
    TFunctionDelegateInstance::Create(result.Instance, InFunctor);
    return result;
  }

  void BindNew(void *InFunctor) {
    std::cout << "TDelegate::BindNew by:" << this << std::endl;
    TFunctionDelegateInstance::Create(this->Instance, InFunctor);
  }

  TFunctionDelegateInstance *Instance;
};

```

对于一个常规声明和绑定行为：

```
  TDelegate delegate;
  delegate.Bind(func);
```

则输出：

```
Empty TDelegate() by:000000D71F4FFBD8
TDelegate::Bind by:000000D71F4FFBD8
Empty TDelegate() by:000000D71F4FFB68
TDelegate::Create by:000000D71F4FFB68
Create(TFunctionDelegateInstance &Base, const void *InFunctor) by:00007FF620AB2370
// 以下两行打印信息在UE原版中应不存在
//FDelegateHandle(GenerateNewHandle):ID(1) by:0000028B63517860
//TCommonDelegateInstance() by:0000028B63517860
// *** Alloc应对应UE原版分配器的Allocate函数
Alloc TFunctionDelegateInstance() by:0000028B63517860
// ID递增，原子操作
FDelegateHandle(GenerateNewHandle):ID(2) by:0000028B63517860
 TCommonDelegateInstance() by:0000028B63517860
TFunctionDelegateInstance(const void *InFunctor) by:0000028B63517860 InFunctor:00007FF620A71000
CreateCopy(TCommonDelegateInstance &Base) by:0000000000000000
// 以下两行打印信息在UE原版中应不存在
//FDelegateHandle(GenerateNewHandle):ID(3) by:0000028B63517640
//TCommonDelegateInstance() by:0000028B63517640
// *** Alloc应对应UE原版分配器的Allocate函数
Alloc TFunctionDelegateInstance() by:0000028B63517640
// 不触发ID递增行为
Empty FDelegateHandle():ID(0) by:0000028B63517640
default copy TCommonDelegateInstance(TCommonDelegateInstance&other) by:0000028B63517640
default copy TFunctionDelegateInstance(TFunctionDelegateInstance& other)  by:0000028B63517640
operator =(TDelegate&& Other) by:000000D71F4FFBD8 ID:2
~TDelegate() by:000000D71F4FFB68
```

而使用修改过后的函数，则输出：

```
Empty TDelegate() by:000000D71F4FFBC8
TDelegate::BindNew by:000000D71F4FFBC8
Create(TFunctionDelegateInstance &Base, const void *InFunctor) by:00007FF620A77A3D
// 以下两行打印信息在UE原版中应不存在
//FDelegateHandle(GenerateNewHandle):ID(4) by:0000028B635178E0
//TCommonDelegateInstance() by:0000028B635178E0
// *** Alloc应对应UE原版分配器的Allocate函数
Alloc TFunctionDelegateInstance() by:0000028B635178E0
// ID递增，原子操作
FDelegateHandle(GenerateNewHandle):ID(5) by:0000028B635178E0
 TCommonDelegateInstance() by:0000028B635178E0
TFunctionDelegateInstance(const void *InFunctor) by:0000028B635178E0 InFunctor:00007FF620A71000
```

对比可得出新方法少9次函数调用，其中Allocate函数少一次。

### 可能存在的问题

Delegate有个行为是只要绑定新的函数上来，那么会先析构旧的函数引用。而新方法里没有显式执行这一行为，那么它会引起问题么？

在DelegateBase.h的文件中存在placement new的重载

```
void * operator new(size_t Size, FDelegateBase& Base){
    return Base.Allocate((int)Size);
}
```

而FDelegateBase的Allocate的函数中本身就携带对旧委托内容的析构行为：

```
void* Allocate(int32 Size){
    if(auto* CurrentInstance = GetDelegateInstanceProtected()){
        CurrentInstance->~IDelegateInstance();
    }
    if(DelegateSize != Size){
        DelegateAllocator.ResizeAllocation(0, Size);
        DelegateSize = Size;
    }
    return DelegateAllocator.GetAllocation();
}
```

所以这里不会产生问题。

### 疑惑

UE为什么要这么写呢？暂时还没有想明白。如果说为了线程安全，但似乎看代码原版实现也不严谨。
