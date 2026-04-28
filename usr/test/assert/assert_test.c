#include <assert.h>
#include <stdio.h>

__attribute__((noinline)) void assert_level3(void)
{
    int x = 1;
    printf("Triggering assertion failure in assert_level3...\n");
    assert(x == 0);
}

__attribute__((noinline)) void assert_level2(void)
{
    assert_level3();
}

__attribute__((noinline)) void assert_level1(void)
{
    assert_level2();
}

int main(int argc, char *argv[])
{
    printf("Assert test program starting...\n");
    assert_level1();
    return 0;
}
