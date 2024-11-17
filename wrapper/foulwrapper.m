#import <stdio.h>
#import <spawn.h>
#import <objc/runtime.h>

#import <Foundation/Foundation.h>

#import <MobileContainerManager/MCMContainer.h>
#import <MobileCoreServices/LSApplicationProxy.h>
#import <MobileCoreServices/LSApplicationWorkspace.h>

static int VERBOSE = 0;

#define MH_MAGIC_64 0xfeedfacf /* the 64-bit mach magic number */
#define MH_CIGAM_64 0xcffaedfe /* NXSwapInt(MH_MAGIC_64) */

#define FAT_MAGIC_64 0xcafebabf
#define FAT_CIGAM_64 0xbfbafeca /* NXSwapLong(FAT_MAGIC_64) */

extern char **environ;

static NSString *shared_shell_path(void) {
  static NSString *_sharedShellPath = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    @autoreleasepool {
      NSArray<NSString *> *possibleShells = @[
        @"/usr/bin/bash",
        @"/bin/bash",
        @"/usr/bin/sh",
        @"/bin/sh",
        @"/usr/bin/zsh",
        @"/bin/zsh",
        @"/var/jb/usr/bin/bash",
        @"/var/jb/bin/bash",
        @"/var/jb/usr/bin/sh",
        @"/var/jb/bin/sh",
        @"/var/jb/usr/bin/zsh",
        @"/var/jb/bin/zsh",
      ];
      NSFileManager *fileManager = [NSFileManager defaultManager];
      for (NSString *shellPath in possibleShells) {
        // check if the shell exists and is regular file (not symbolic link) and
        // executable
        NSDictionary<NSFileAttributeKey, id> *shellAttrs =
            [fileManager attributesOfItemAtPath:shellPath error:nil];
        if ([shellAttrs[NSFileType] isEqualToString:NSFileTypeSymbolicLink]) {
          continue;
        }
        if (![fileManager isExecutableFileAtPath:shellPath]) {
          continue;
        }
        _sharedShellPath = shellPath;
        break;
      }
    }
  });
  return _sharedShellPath;
}

int system_call_exec(const char *ctx) {
  const char *shell_path = [shared_shell_path() UTF8String];
  const char *args[] = {shell_path, "-c", ctx, NULL};
  pid_t pid;
  int posix_status =
      posix_spawn(&pid, shell_path, NULL, NULL, (char **)args, environ);
  if (posix_status != 0) {
    errno = posix_status;
    fprintf(stderr, "[exec] posix_spawn, %s (%d)\n", strerror(errno), errno);
    return posix_status;
  }
  pid_t w;
  int status;
  do {
    w = waitpid(pid, &status, WUNTRACED | WCONTINUED);
    if (w == -1) {
      fprintf(stderr, "[exec] waitpid %d, %s (%d)\n", pid, strerror(errno), errno);
      return errno;
    }
    if (WIFEXITED(status) && WEXITSTATUS(status) != 0) {
      fprintf(stderr, "[exec] pid %d exited, status=%d\n", pid, WEXITSTATUS(status));
    } else if (WIFSIGNALED(status) && WTERMSIG(status) != 9) {
      fprintf(stderr, "[exec] pid %d killed by signal %d\n", pid, WTERMSIG(status));
    } else if (WIFSTOPPED(status)) {
      fprintf(stderr, "[exec] pid %d stopped by signal %d\n", pid, WSTOPSIG(status));
    } else if (WIFCONTINUED(status)) {
      fprintf(stderr, "[exec] pid %d continued\n", pid);
    }
  } while (!WIFEXITED(status) && !WIFSIGNALED(status));
  if (WIFSIGNALED(status)) {
    return WTERMSIG(status);
  }
  return WEXITSTATUS(status);
}

NSString *escape_arg(NSString *arg) {
  return [arg stringByReplacingOccurrencesOfString:@"\'" withString:@"'\\\''"];
}

NSString *normalize_path(NSString *p) {
  NSString *curPath = [[NSFileManager defaultManager] currentDirectoryPath];

  // check contains `procursus` in `curPath`
  if ([curPath rangeOfString:@"procursus"].location != NSNotFound) {
    // replace curPath in p
    p = [p stringByReplacingOccurrencesOfString:curPath withString:@""];
  }

  return p;
}

@interface LSApplicationProxy ()
- (NSString *)shortVersionString;
@end

int main(int argc, char *argv[]) {
  if (argc < 2) {
    fprintf(stderr, "usage: foulwrapper2 (application name or application "
                    "bundle identifier)\n");
    return 1;
  }

  /* Use APIs in `LSApplicationWorkspace`. */
  NSMutableDictionary *appMaps = [NSMutableDictionary dictionary];
  LSApplicationWorkspace *workspace = [LSApplicationWorkspace defaultWorkspace];
  for (LSApplicationProxy *appProxy in [workspace allApplications]) {
    NSString *appId = [appProxy applicationIdentifier];
    NSString *appName = [appProxy localizedName];
    if (appId && appName) {
      appMaps[appId] = appName;
    }
  }

  NSString *targetIdOrName = [NSString stringWithUTF8String:argv[1]];
  NSString *targetId = nil;
  for (NSString *appId in appMaps) {
    if ([appId isEqualToString:targetIdOrName] ||
        [appMaps[appId] isEqualToString:targetIdOrName]) {
      targetId = appId;
      break;
    }
  }

  if (!targetId) {
    fprintf(stderr, "application \"%s\" not found\n", argv[1]);
    return 1;
  }

  fprintf(stderr, "[start] Target app -> %s\n", [targetId UTF8String]);

  /* MobileContainerManager: locate app bundle container path */
  /* `LSApplicationProxy` cannot provide correct values of container URLs since iOS 12. */
  NSError *error = nil;
  id aClass = objc_getClass("MCMAppContainer");
  assert([aClass respondsToSelector:@selector(containerWithIdentifier:error:)]);

  MCMContainer *container = [aClass containerWithIdentifier:targetId error:&error];
  NSString *targetPath = [[container url] path];
  if (!targetPath) {
    fprintf(stderr, "Application \"%s\" does not have a bundle container: %s\n", argv[1], [[error localizedDescription] UTF8String]);
    return 1;
  }

  /* Try open */
  // fprintf(stderr, "[open] Try open app with bundle %s\n", [targetId UTF8String]);
  // system_call_exec([[NSString stringWithFormat:@"fopenn '%@'", escape_arg(targetId)] UTF8String]);

  // close the app with kill command
  // get uuid in targetPath /private/var/containers/Bundle/Application/D271123F-AAEF-4CC7-A9E6-382DD35C2343
  // NSString *appUuid = [targetPath lastPathComponent];
  // NSString *killCmd = [NSString stringWithFormat:@"set -e; shopt -s dotglob; ps aux | grep -i 'Application/%@' | tr -s ' ' | cut -d ' ' -f 2 | xargs kill -9 &> /dev/null; shopt -u dotglob;", escape_arg(appUuid)];
  // system_call_exec([killCmd UTF8String]);

  /* decrypt */
  fprintf(stderr, "[dump] Start dumping...\n");

  /* LSApplicationProxy: get app info */
  LSApplicationProxy *appProxy = [LSApplicationProxy applicationProxyForIdentifier:targetId];
  assert(appProxy);

  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSString *homeDir = [fileManager currentDirectoryPath];
  NSString *workingDir = [NSString stringWithFormat:@"appdecrypt/%@_%@", [appProxy applicationIdentifier], [appProxy shortVersionString]];

  NSString *dumpPathName = [NSString stringWithFormat:@"%@/dump", workingDir];
  NSString *outPath = [NSString stringWithFormat:@"%@/%@", homeDir, dumpPathName];

  // check outPath exists
  BOOL isDir = true;
  if ([fileManager fileExistsAtPath:outPath isDirectory:&isDir]) {
    fprintf(stderr, "[dump] Dump directory already exists. AUTO CLEANUP!\n");
    if ([fileManager removeItemAtPath:outPath error:&error]) {} else {
      fprintf(stderr, "[dump] Failed to remove directory: %s\n", [normalize_path(outPath) UTF8String]);
      return 1;
    }
  }

  if ([fileManager createDirectoryAtPath:outPath withIntermediateDirectories:YES attributes:nil error:&error]) {} else {
    fprintf(stderr, "[dump] Failed to create directory: %s\n", [normalize_path(outPath) UTF8String]);
    return 1;
  }

  fprintf(stderr, "[dump] Target @ -> %s\n", [targetPath UTF8String]);
  fprintf(stderr, "[dump] Dumping to .%s\n", [normalize_path(outPath) UTF8String]);

  NSString *decryptPath = [NSString stringWithFormat:@".%@", normalize_path(outPath)];
  system_call_exec([[NSString stringWithFormat:@"d3crypt '%@' '%@' -b", escape_arg(targetPath), escape_arg(decryptPath)] UTF8String]);

  // check .fail in outPath
  NSString *failPath = [NSString stringWithFormat:@"%@/.fail", outPath];
  if ([fileManager fileExistsAtPath:failPath]) {
    // print error in .fail
    NSString *failContent = [NSString stringWithContentsOfFile:failPath encoding:NSUTF8StringEncoding error:nil];
    fprintf(stderr, "===== ERROR ======\n%s\n===== >>*<< ======\n", [failContent UTF8String]);

    fprintf(stderr, "[dump] Failed to dump!\n");

    fprintf(stderr, "[clean] Remove temp %s\n", [workingDir UTF8String]);
    [fileManager removeItemAtPath:workingDir error:nil];
    return 1;
  }

  fprintf(stderr, "[dump] Successful!\n");

  fprintf(stderr, "[archive] Start create ipa...\n");
  NSString *payloadPathName = [NSString stringWithFormat:@"%@/Payload", workingDir];
  NSString *payloadPath = [NSString stringWithFormat:@"%@/%@", homeDir, payloadPathName];

  // check payloadPath exists
  if ([fileManager fileExistsAtPath:payloadPath isDirectory:&isDir]) {
    fprintf(stderr, "[archive] Payload directory already exists. AUTO CLEANUP!\n");
    if ([fileManager removeItemAtPath:payloadPath error:&error]) {} else {
      fprintf(stderr, "[archive] Failed to remove directory: %s\n", [normalize_path(payloadPath) UTF8String]);
      return 1;
    }
  }

  fprintf(stderr, "[archive] Copying app files to .%s\n", [normalize_path(payloadPath) UTF8String]);
  BOOL didCopy = [fileManager copyItemAtPath:targetPath toPath:payloadPath error:&error];
  if (!didCopy) {
    fprintf(stderr, "[archive] Failed to copy Payload: %s\n", [normalize_path(payloadPath) UTF8String]);
    return 1;
  }

  // override content from decryptPath to payloadPath
  fprintf(stderr, "[archive] Sync decrypted files\n");
  NSEnumerator *dumpedFiles = [[NSFileManager defaultManager] enumeratorAtPath:outPath];
  NSString *dumpedFile = nil;
  while (dumpedFile = [dumpedFiles nextObject]) {

    NSString *dumpedFilePath = [outPath stringByAppendingPathComponent:dumpedFile];
    // check if dumpedFile is a directory
    BOOL isDir = true;
    if ([fileManager fileExistsAtPath:dumpedFilePath isDirectory:&isDir] && isDir) {
      continue;
    }

    NSString *payloadFilePath = [payloadPath stringByAppendingPathComponent:dumpedFile];
    // fprintf(stderr, "[archive] Sync %s\n", [dumpedFile UTF8String]);

    // remove old file
    if ([fileManager fileExistsAtPath:payloadFilePath]) {
      [fileManager removeItemAtPath:payloadFilePath error:nil];
    }

    // copy new file
    [fileManager copyItemAtPath:dumpedFilePath toPath:payloadFilePath error:nil];
  }

  // remove unused files
  NSString *mobileContainerManager = [payloadPath stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
  NSString *bundleMetadata = [payloadPath stringByAppendingPathComponent:@"BundleMetadata.plist"];
  NSString *iTunesMetadata = [payloadPath stringByAppendingPathComponent:@"iTunesMetadata.plist"];
  [fileManager removeItemAtPath:mobileContainerManager error:nil];
  [fileManager removeItemAtPath:bundleMetadata error:nil];
  [fileManager removeItemAtPath:iTunesMetadata error:nil];
  fprintf(stderr, "[archive] Removed unused files.\n");

  // remove UISupportedDevices
  NSArray *payloadContents = [fileManager contentsOfDirectoryAtPath:payloadPath error:nil];
  for (NSString *file in payloadContents) {
    if ([file hasSuffix:@".app"]) {
      NSString *infoPlistPath = [payloadPath stringByAppendingPathComponent:[file stringByAppendingPathComponent:@"Info.plist"]];
      NSMutableDictionary *infoPlist = [NSMutableDictionary dictionaryWithContentsOfFile:infoPlistPath];
      [infoPlist removeObjectForKey:@"UISupportedDevices"];
      [infoPlist setObject:[appProxy localizedName] forKey:@"CFBundleDisplayName"];
      [infoPlist writeToFile:infoPlistPath atomically:YES];

      NSString *signPath = [payloadPath stringByAppendingPathComponent:[file stringByAppendingPathComponent:@"decrypt.day"]];
      [fileManager createFileAtPath:signPath contents:[@"und3fined" dataUsingEncoding:NSUTF8StringEncoding] attributes:nil];
    }
  }

  // /* zip: archive */
  fprintf(stderr, "[archive] Create archive ipa...\n");
  NSString *archiveName = [NSString stringWithFormat:@"appdecrypt/%@_%@_und3fined.ipa", [appProxy applicationIdentifier], [appProxy shortVersionString]];
  NSString *archivePath = [NSString stringWithFormat:@"%@/%@", homeDir, archiveName];

  // force remove archivePath
  BOOL didClean = [fileManager removeItemAtPath:archivePath error:nil];

  fprintf(stderr, "[archive] Save to .%s\n", [normalize_path(archivePath) UTF8String]);

  int zipStatus = system_call_exec([[NSString stringWithFormat:@"set -e; shopt -s dotglob; cd '%@'; zip -rq '%@' Payload; shopt -u dotglob;",
                                  escape_arg(workingDir),
                                  escape_arg(archivePath)] UTF8String]);

  if (zipStatus != 0) {
    fprintf(stderr, "[archive] Failed to archive ipa!\n");
    return 1;
  }

  fprintf(stderr, "[dump] Remove temp %s\n", [workingDir UTF8String]);
  [fileManager removeItemAtPath:workingDir error:nil];

  fprintf(stderr, "[dump] Done!\n");
  fprintf(stdout, "%s\n", [archiveName UTF8String]);
  fflush(stdout);
  return 0;
}
