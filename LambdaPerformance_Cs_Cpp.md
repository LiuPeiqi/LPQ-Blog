# C#和C++11的Lambda闭包性能对比
Lambda表达式和闭包是比较方便的语法糖，但是它对C#和C++11会分别有多大的开销呢？
>C#使用QueryPerformanceFrequency来计时，C++11使用chrono::high_resolution_clock::now来计时
C#使用VS2017 框架.Net 4.6.1 Release编译，首选平台是Any CPU，允许不安全代码。
C++使用VS2017 Release Win32编译，\O2 \Oi
运行电脑环境：Windows7 SP1 64bit i5-2320 内存8G

#### 先看C#代码
为防止GC，先主动用fixed来吧循环部分括起来，这个结果可以作为标准参考。：
```
public int OriginalCompare(out double cost){
    int count = 0;
    unsafe{
        fixed (double* data_pointer = &data[0]){
            QueryPerformanceFrequency(out long frequency);
            QueryPerformanceCounter(out long start);
            double* beg = data_pointer;
            double* end = data_pointer + data.Length;
            while(beg < end){
                if(beg[1] >= beg[0] && beg[1] < beg[2]){
                    ++count;
                }
                beg += 3;
            }
            QueryPerformanceCounter(out long finish);
            cost = (finish - start) * 1.0 / frequency;
        }
    }
    return count;
}
```
未做特殊防GC处理的代码：
```
public int NormalCompare(out double cost){
    int count = 0;
    QueryPerformanceFrequency(out long frequency);
    QueryPerformanceCounter(out long start);
    for (int i = 0; i < data.Length;){
        if(data[i+1]>=data[i] && data[i+1] < data[i + 2]){
            ++count;
        }
        i += 3;
    }
    QueryPerformanceCounter(out long finish);
    cost = (finish - start) * 1.0 / frequency;
    return count;
}
```
接下来是有闭包Lambda表达式。
```
public int CloserCompare(out double cost){
    int count = 0;
    Func<double, double, Func<double, bool>> generate = (bottom, top) =>{
        return (x) =>{
            return x >= bottom && x <= top;
        };
    };
    QueryPerformanceFrequency(out long frequency);
    QueryPerformanceCounter(out long start);
    for (int i = 0; i < data.Length;){
        if (generate(data[i],data[i+2])(data[i+1])){
            ++count;
        }
        i += 3;
    }
    QueryPerformanceCounter(out long finish);
    cost = (finish - start) * 1.0 / frequency;
    return count;
}
```
后面试一下使用类来主动实现的方案。
```
internal class ClassCompare{
    private double _bottom, _top;
    public ClassCompare(double bottom, double top){
        _bottom = bottom;
        _top = top;
    }
    public bool Comparer(double x){
        return x >= _bottom && x < _top;
    }
}
public int InternalClassCompare(out double cost){
    int count = 0;
    QueryPerformanceFrequency(out long frequency);
    QueryPerformanceCounter(out long start);
    for (int i = 0; i < data.Length;){
        if (new ClassCompare(data[i], data[i + 2]).Comparer(data[i + 1])){
            ++count;
        }
        i += 3;
    }
    QueryPerformanceCounter(out long finish);
    cost = (finish - start) * 1.0 / frequency;
    return count;
}
```
#### C#的结果
测试30M次，数组是用random填充的。输出的结果平均每次的时间，单位us
>Original Compare:       0.00817299978618773     us/per
Normal Compare:         0.00906182025514931     us/per
Closer Compare:         0.0302088005131495      us/per
Internal class Compare: 0.0292144879196066      us/per

这个结果基本符合预期吧，使用C#使用指针貌似在这种情况下没有带来明显优势，闭包lambda表达式比不用的情况下慢了2倍左右。猜测可能的原因就是构造对象和GC带来的吧，这个可能要再想办法设计一个量化的实验方案。

#### 那么，C++的表现呢
为了表现同样的环境，C++使用new来在堆上分配数组内存，也用random来填充。
作为参考的代码：
```
int OriginalCompare(double &cost) {
    auto beg = GetData();
    auto end = beg + data_size;
    int count = 0;
    auto start = chrono::high_resolution_clock::now();
    while (beg < end) {
        if (beg[1] >= beg[0] && beg[1] < beg[2]) {
            ++count;
        }
        beg += 3;
    }
    auto finish = chrono::high_resolution_clock::now();
    cost = chrono::duration_cast<chrono::nanoseconds>(finish - start).count() / 1e9;
    return count;
}
```
使用lambda闭包的代码：
```
int CloserCompare(double & cost) {
    auto beg = GetData();
    auto end = beg + data_size;
    int count = 0;
    auto generate = [](auto bottom, auto top) {return [=](auto x) {return x >= bottom && x < top; }; };
    auto start = chrono::high_resolution_clock::now();
    while (beg < end) {
        if (generate(beg[0],beg[2])(beg[1])) {
            ++count;
        }
        beg += 3;
    }
    auto finish = chrono::high_resolution_clock::now();
    cost = chrono::duration_cast<chrono::nanoseconds>(finish - start).count() / 1e9;
    return count;
}
```
使用类和仿函数来实现的代码：
```
class _ClassCompare {
public:
    _ClassCompare(double bottom, double top) :_bottom(bottom), _top(top) {}
    bool operator()(double x) { return x >= _bottom && x < _top; }
private:
    double _bottom, _top;
};

int ClassCompare(double & cost) {
    auto beg = GetData();
    auto end = beg + data_size;
    int count = 0;
    auto start = chrono::high_resolution_clock::now();
    while (beg < end) {
        if (_ClassCompare(beg[0], beg[2])(beg[1])) {
            ++count;
        }
        beg += 3;
    }
    auto finish = chrono::high_resolution_clock::now();
    cost = chrono::duration_cast<chrono::nanoseconds>(finish - start).count() / 1e9;
    return count;
}
```
对于c++来说，光有上面的对比不够令人信服，因为如上的对象是建立在栈上的，这样会比在堆上新建对象快的多。那么下面是两个参考。第一段是new一个对象，最后结束的时候delete；第二段是使用智能指针shared_ptr来模拟C#中引用计数的情况：
```
int NewClassCompare(double & cost) {
    auto beg = GetData();
    auto end = beg + data_size;
    int count = 0;
    auto start = chrono::high_resolution_clock::now();
    while (beg < end) {
        auto obj = new _ClassCompare(beg[0], beg[2]);
        if ((*obj)(beg[1])) {
            ++count;
        }
        beg += 3;
        delete obj;
    }
    auto finish = chrono::high_resolution_clock::now();
    cost = chrono::duration_cast<chrono::nanoseconds>(finish - start).count() / 1e9;
    return count;
}

int SharedClassCompare(double & cost) {
    auto beg = GetData();
    auto end = beg + data_size;
    int count = 0;
    auto start = chrono::high_resolution_clock::now();
    while (beg < end) {
        auto obj = make_shared<_ClassCompare>(beg[0], beg[2]);
        if ((*obj)(beg[1])) {
            ++count;
        }
        beg += 3;
    }
    auto finish = chrono::high_resolution_clock::now();
    cost = chrono::duration_cast<chrono::nanoseconds>(finish - start).count() / 1e9;
    return count;
}
```
####C++11的结果
>OriginalCompare         :0.006153       us/per
CloserCompare           :0.007234       us/per
ClassCompare            :0.006896       us/per
NewClassCompare         :0.064683       us/per
SharedClassCompare      :0.080803       us/per

这个结果说实话，有点在意料之外，对于存在闭包和仿函数的情况，竟然被编译器优化的跟原始的代码不相上下。现代编译器基本上可以算是实现了C++语法糖不降低程序性能的纲领吧。而new对象和shared的表现则非常不友好，之前有看相关文章，可能这就是一种内存振荡吧，程序在不断新建和销毁同一个对象。处在这种情况下，有托管的语言则好很多。C++多出来的时间会不会是因为要不停的释放内存？因为毕竟构造过程大家都要做的，C#可能比C++少的过程就是C# GC集中释放内存，C++是每一次都在释放内存。
#### 那可不可以模仿一下C#呢？
我进行了一个不严谨的尝试：
```
int LikeCSCompare(double &cost) {
    auto beg = GetData();
    auto end = beg + data_size;
    int count = 0;
    using Ptr = shared_ptr<_ClassCompare>;
    auto start = chrono::high_resolution_clock::now();
    vector<Ptr> pool(test_count);
    int index = 0;
    while (beg < end) {
        Ptr obj;
        try {
            obj = make_shared<_ClassCompare>(beg[0], beg[2]);
        }
        catch (...) {
            pool.clear();
            index = 0;
            obj = make_shared<_ClassCompare>(beg[0], beg[2]);
        }
        ++index;
        if ((*obj)(beg[1])) {
            ++count;
        }
        beg += 3;
    }
    auto finish = chrono::high_resolution_clock::now();
    cost = chrono::duration_cast<chrono::nanoseconds>(finish - start).count() / 1e9;
    return count;
}
```
利用shared和vector来模仿gc的延后释放的过程，而结果：
>LikeCSCompare   :0.086024       us/per

然并卵！这个词在这里很准确。

### 结论
* C++编译器优化确实nb。
* C#托管确实nb。
* C#还是不要在关键（循环里）位置使用lambda。
