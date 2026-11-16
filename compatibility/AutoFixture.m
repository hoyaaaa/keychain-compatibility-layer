#import <AppKit/AppKit.h>

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        NSString *directory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Keychain Compatibility Layer/runtime"];
        NSString *marker = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.loaded",getpid()]];
        NSString *event = [NSString stringWithFormat:@"%d %@\n",getpid(),[NSFileManager.defaultManager fileExistsAtPath:marker] ? @"loaded" : @"vanilla"];
        NSString *path = [directory stringByAppendingPathComponent:@"fixture-launches.log"];
        int fd = open(path.fileSystemRepresentation,O_CREAT|O_WRONLY|O_APPEND,0600);
        if (fd >= 0) { write(fd,event.UTF8String,strlen(event.UTF8String));close(fd); }
        [NSApp run];
    }
    return 0;
}
