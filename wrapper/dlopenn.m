/**
* dlopenn.m
* This program demonstrates how to use dlopen to load a shared library.
*/
#include <dlfcn.h>
#include <stdio.h>

int main(int argc, char **argv) {
  void *(*sym_dlopen)(const char *, int) = dlsym(RTLD_DEFAULT, "dlopen");
  for (int i = 1; i < argc; i++) {
    void *handle = sym_dlopen(argv[i], RTLD_NOW);
    dlclose(handle);
  }
  return 0;
}
