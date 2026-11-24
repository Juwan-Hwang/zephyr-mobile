// 16 KB 模拟器加载探针：逐个 dlopen 参数里的 .so，打印 OK / FAIL + dlerror()。
// 由 tools/android-16k/load-test.sh 用 NDK clang 交叉编译后推到模拟器 /data/local/tmp 运行，不进 App。
#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>

int main(int argc, char **argv) {
  int fail = 0;
  printf("PAGE_SIZE(sysconf)=%ld\n", sysconf(_SC_PAGESIZE));
  for (int i = 1; i < argc; i++) {
    void *h = dlopen(argv[i], RTLD_NOW | RTLD_GLOBAL);
    if (h) {
      printf("OK   %s\n", argv[i]);
    } else {
      printf("FAIL %s: %s\n", argv[i], dlerror());
      fail = 1;
    }
    fflush(stdout);
  }
  return fail;
}
