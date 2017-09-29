# C# Struct的复制性能

开始用class和float[]写了一个Matrix类，后来担心GC开销，于是用struct重写了一个固定大小的Matrix4x4。结果表明CPU占用率上升了但是实际性能下降了，那么，是因为struct作为函数参数多次传递引发额外复制造成的么？在C++中，常规的使用方法是使用const T& 常引用的办法来避免额外的复制操作，而C#中只有ref，而没有常引用。那么就先使用ref作为替代研究一下。

先看Matrix4x4的定义

```C#
public struct Matrix4x4{
    public float at00, at01, at02, at03;
    public float at10, at11, at12, at13;
    public float at20, at21, at22, at23;
    public float at30, at31, at32, at33;

    public Matrix4x4(ref Matrix4x4 right){
        at00 = right.at00;at01 = right.at01;at02 = right.at02;at03 = right.at03;
        at10 = right.at10;at11 = right.at11;at12 = right.at12;at13 = right.at13;
        at20 = right.at20;at21 = right.at21;at22 = right.at22;at23 = right.at23;
        at30 = right.at30;at31 = right.at31;at32 = right.at32;at33 = right.at33;
    }

    public Matrix4x4(Matrix4x4 right){
        at00 = right.at00;at01 = right.at01;at02 = right.at02;at03 = right.at03;
        at10 = right.at10;at11 = right.at11;at12 = right.at12;at13 = right.at13;
        at20 = right.at20;at21 = right.at21;at22 = right.at22;at23 = right.at23;
        at30 = right.at30;at31 = right.at31;at32 = right.at32;at33 = right.at33;
    }

    public float Sum(){
        return at00 + at01 + at02 + at03
            + at10 + at11 + at12 + at13
            + at20 + at21 + at22 + at23
            + at30 + at31 + at32 + at33;
    }
}
```

先定义了两个拷贝构造函数，其中一个是引用传参，Sum函数用于防止编译器把可能的无实际作用的代码给优化掉。先看一下这两个构造函数的性能区别吧：

```C#
    static float OnlySum(out double total){
        Matrix4x4 m = data[0];
        QueryPerformanceFrequency(out long freq);
        QueryPerformanceCounter(out long start);
        float res = 0;
        for(int i = 0; i < TEST_COUNT; ++i){
            res += m.Sum();
        }
        QueryPerformanceCounter(out long finish);
        total = (finish - start) * 1.0 / freq;
        return res;
    }

    static float CopyConstruct(out double total){
        QueryPerformanceFrequency(out long freq);
        QueryPerformanceCounter(out long start);
        float res = 0;
        for(int i = 0; i < TEST_COUNT; ++i)            {
            var m = new Matrix4x4(data[i]);
            res += m.Sum();
        }
        QueryPerformanceCounter(out long finish);
        total = (finish - start) * 1.0 / freq;
        return res;
    }

    static float RefCopyConstruct(out double total){
        QueryPerformanceFrequency(out long freq);
        QueryPerformanceCounter(out long start);
        float res = 0;
        for (int i = 0; i < TEST_COUNT; ++i){
            var m = new Matrix4x4(ref data[i]);
            res += m.Sum();
        }
        QueryPerformanceCounter(out long finish);
        total = (finish - start) * 1.0 / freq;
        return res;
    }
```

上面三个是用于测试的函数，TEST_COUNT是1M次，OnlySum用于测量只执行Sum函数的时间，后续Copy或Ref Copy测量的时间会减去OnlySum的执行时间。例如 copy total cost - only total cost。具体运行结果：

```
Only Sum Matrix4x4:  0.00543733162283515s
Copy Construct :0.0173047680s,  takeoff sum :0.0118674364s
Ref  Construct :0.0143445799s,  takeoff sum :0.0089072482s
```

通过结果可以看到性能略有提升，但是相对有限，使用ref会节省大约0.003时间。后续再尝试运算符重载的时候，发现运算符重载函数不能使用ref制定参数，那么运算符重载的参数拷贝会造成多大负担呢？先看三个矩阵加法的定义。

```C#
    public static Matrix4x4 operator +(Matrix4x4 m1, Matrix4x4 m2){
        Matrix4x4 mat;
        mat.at00 = m1.at00 + m2.at00; mat.at01 = m1.at01 + m2.at01; mat.at02 = m1.at02 + m2.at02; mat.at03 = m1.at03 + m2.at03;
        mat.at10 = m1.at10 + m2.at10; mat.at11 = m1.at11 + m2.at11; mat.at12 = m1.at12 + m2.at12; mat.at13 = m1.at13 + m2.at13;
        mat.at20 = m1.at20 + m2.at20; mat.at21 = m1.at21 + m2.at21; mat.at22 = m1.at22 + m2.at22; mat.at23 = m1.at23 + m2.at23;
        mat.at30 = m1.at30 + m2.at30; mat.at31 = m1.at31 + m2.at31; mat.at32 = m1.at32 + m2.at32; mat.at33 = m1.at33 + m2.at33;
        return mat;
    }
    public static Matrix4x4 Add(ref Matrix4x4 m1, ref Matrix4x4 m2){
        Matrix4x4 mat;
        mat.at00 = m1.at00 + m2.at00; mat.at01 = m1.at01 + m2.at01; mat.at02 = m1.at02 + m2.at02; mat.at03 = m1.at03 + m2.at03;
        mat.at10 = m1.at10 + m2.at10; mat.at11 = m1.at11 + m2.at11; mat.at12 = m1.at12 + m2.at12; mat.at13 = m1.at13 + m2.at13;
        mat.at20 = m1.at20 + m2.at20; mat.at21 = m1.at21 + m2.at21; mat.at22 = m1.at22 + m2.at22; mat.at23 = m1.at23 + m2.at23;
        mat.at30 = m1.at30 + m2.at30; mat.at31 = m1.at31 + m2.at31; mat.at32 = m1.at32 + m2.at32; mat.at33 = m1.at33 + m2.at33;
        return mat;
    }
    public void Add(ref Matrix4x4 m){
        at00 += m.at00; at01 += m.at01; at02 += m.at02; at03 += m.at03;
        at10 += m.at10; at11 += m.at11; at12 += m.at12; at13 += m.at13;
        at20 += m.at20; at21 += m.at21; at22 += m.at22; at23 += m.at23;
        at30 += m.at30; at31 += m.at31; at32 += m.at32; at33 += m.at33;
    }
```

operator+和一个static Add用于对比重载操作符中是否对非ref参数造成额外开销。测试函数基本类似上面的复制构造函数：在主动复制的位置变成了“var m = data[i] + data[i];”这样的加法操作。
看一下运行结果：

```
Operator+      :0.0484231773s,  takeoff sum :0.0430463973s
Ref  Add1      :0.0462727389s,  takeoff sum :0.0408959589s
Ref  Add2      :0.0261778063s,  takeoff sum :0.0208010263s
```

Add2的结果基本上是没有复制的，时间可以作为Matrix执行加法的参考。operator+参数执行两次复制，返回值执行一次复制，临时变量可能执行一次构造。Add函数参数使用ref，如果没有复制的话，只有临时变量执行了一次构造和返回执行一次复制。对比operator，应该节省两次复制的时间，但是从结果上来看，似乎operator中的参数没有ref的这件事并没有多大影响（多了0.00215），为了便利性，使用operator重载还是非常方便的。那么void Add的对比函数比operator+少的一半的时间是因为return的值引起的吗？重新修改一下是static Add的定义：

```C#
public static void Add(ref Matrix4x4 m1, ref Matrix4x4 m2, out Matrix4x4 mat);
public static void Add(Matrix4x4 m1,  Matrix4x4 m2, out Matrix4x4 mat)
```

使用out来减少一个局部变量和复制，作为对比，特意又加入一个传入参数的不是ref的对比。那么看一下这两个结果：

```
Ref  Add3      :0.0173745563s,  takeoff sum :0.0118756468s
Ref  Add4      :0.0242736797s,  takeoff sum :0.0186967714s
```

结果有一些意外，使用了out作为返回值的函数都大大低于了前面的结果。理论上返回值的复制跟参数的复制应该区别不大才对，如果在参数上使用ref没有产生这么的变化，out的结果也应该只有小幅提升才合理，用上面的结果参考一下，复制构造的时间大概是0.012，那么使用out的耗时应该是0.041（两个参数ref返回值为Matrix4x4）-0.012 = 0.029左右，这个值还是比Add3的结果高出了不少。像这样发生少了两倍的耗时，是应该还有其他状况发生的。参考C++中的情况，我猜测的一个可能是使用out的函数发生了内联（inline），这样不仅减少了临时变量和返回值的复制，还减少了一次函数调用。

### 结论
ref和out确实能带来一定的性能提升，但是如果恰当的写法能让编译器发生内联的话（猜测，还没有理论依据能表明out以及无复杂函数操作一定能使编译器触发内联），还是有非常显著的效果的。但是这个的使用场景也相对有限：

1. operator能带来便利性（级联操作）和提升可读性
2. ref没有const的限定，使用ref表明函数内部可能对外部进行修改，这给调用方带来了心智负担。
3. 这一点也是猜测，使用ref并没有增加对struct参数的引用计数，如果这个struct是在堆上的，比如一个struct[]的某一项data[i]作为了ref参数传入到了其他线程中的函数里，而外部的struct[]正好被GC回收，ref可能就会是一个无效引用了。为了验证这一点，可能还要再想办法设计一个实验，暂时我还没有头绪。
4. 想办法简化函数操作，争取让编译器能优化内联还是非常有效的。