---
layout: post
title: "矩阵转置的效率验证"
date: 2017-09-09 
tags: C++  
---

近期在学习矩阵运算的轮子，其中要做矩阵的转置。我第一个想法是新建一个矩阵，然后把要转置的内容复制过去。后来又有点犹豫，新开辟一块内存是不是不如在原位交换各个数值，再交换一下行列效率高呢？

原位交换的思路大致如下：
```C++
long long getNext(long long i, long long m, long long n){
	return (i%n)*m + i / n;  //[row, col] == [i/n, i%n];
}
long long getPre(long long i, long long m, long long n){
	return (i%m)*n + i / m;
}
void movedata(long long *mtx, long long i, long long m, long long n){
	long long temp = mtx[i];
	long long cur = i;
	long long pre = getPre(cur, m, n);
	while (pre != i){
		mtx[cur] = mtx[pre];
		cur = pre;
		pre = getPre(cur, m, n);
	}
	mtx[cur] = temp;
}
void transpose(long long *mtx, long long m, long long n)
{
	for (long long i = 0; i<m*n; ++i){
		long long next = getNext(i, m, n);
		while (next > i){
			next = getNext(next, m, n);
        }
		if (next == i){
			movedata(mtx, i, m, n);
        }
	}
}
```
新分配内存很简单,按列存入新行中就行
```C++
void transpose_copy(long long *&mat, long long m, long long n) {
	long long * tmat = new long long[m*n];
	long long * iter = tmat;
	for (long long i = 0; i < n; ++i) {
		long long *col_iter = mat + i;
		for (long long j = 0; j < m; ++j) {
			*iter++ = *col_iter;
			col_iter += n;
		}
	}
	delete[] mat;
	mat = tmat;
	return;
}
```
代码对比完，直观上看，原位交换虽然省内存，但是乘除模的运算非常多，可能效率并不高。还是实际测试一下,行列随机生成的最大范围1920:

i7 4770k, vs2015, x86, release：
```
Transpose.exe 188 930
inplace:33.907ms
copy   :0.79ms
Transpose.exe 1540 729
inplace:287.524ms
copy   :9.289ms
Transpose.exe 1501 573
inplace:206.993ms
copy   :6.884ms
Transpose.exe 980 543
inplace:115.863ms
copy   :3.359ms
Transpose.exe 1097 1832
inplace:324.641ms
copy   :11.843ms
Transpose.exe 1069 1372
inplace:257.434ms
copy   :8.64ms
Transpose.exe 1682 1901
inplace:709.074ms
copy   :26.29ms
```
结果显示，还是复制来的快！
