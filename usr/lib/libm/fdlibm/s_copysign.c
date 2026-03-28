/* @(#)s_copysign.c 1.3 95/01/18 */
/*
 * ====================================================
 * Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
 *
 * Developed at SunSoft, a Sun Microsystems, Inc. business.
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice 
 * is preserved.
 * ====================================================
 */

#include "fdlibm.h"

#ifdef __STDC__
	double copysign(double x, double y)
#else
	double copysign(x,y)
	double x,y;
#endif
{
	__HI(x) = (__HI(x)&0x7fffffff)|(__HI(y)&0x80000000);
        return x;
}
