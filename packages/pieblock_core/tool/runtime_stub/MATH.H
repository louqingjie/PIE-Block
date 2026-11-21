/* Keil C251 风格 MATH.H 的 gcc 验证桩：生成的表达式代码在 Keil 分支包含
 * "MATH.H"（SDCC 分支用 <math.h> + atan2f/sqrtf）。gcc 冒烟走 Keil 宏路径。
 *
 * 这里不能写 #include <math.h>：Windows 文件系统大小写不敏感，-I tool/runtime_stub
 * 下的 <math.h> 又会命中本文件，而 include guard 已定义，系统 math.h 永远进不来；
 * gcc 14+ 把隐式声明 atan2/sqrt 当错误，冒烟编译就会失败。显式声明这两个函数即可。
 */
#ifndef PB_RUNTIME_STUB_MATH_H
#define PB_RUNTIME_STUB_MATH_H

extern double atan2(double y, double x);
extern double sqrt(double x);

#define atan2 atan2
#define sqrt sqrt

#endif
