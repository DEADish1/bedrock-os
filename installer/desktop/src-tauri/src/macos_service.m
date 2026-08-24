#import <Foundation/Foundation.h>
#import <ServiceManagement/ServiceManagement.h>
#import <dispatch/dispatch.h>
#include <fcntl.h>
#include <stdint.h>
#include <sys/disk.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <unistd.h>

static NSString *const BRWriterServiceName = @"com.bedrock.server.installer.writer";
static NSString *const BRWriterPlistName = @"com.bedrock.server.installer.writer.plist";

enum {
    BRWriterRejected = 1,
    BRWriterPreflightOnly = 3,
    BRWriterRequiresApproval = 4,
    BRWriterRegistrationFailed = 5,
    BRWriterConnectionFailed = 6,
};

typedef void (*BRProgressCallback)(
    const uint8_t *bytes,
    uintptr_t length,
    void *context);

extern int32_t bedrock_macos_handle_writer_request(
    const uint8_t *bytes,
    uintptr_t length,
    BRProgressCallback progress,
    void *context);

static int32_t bedrock_macos_open_validated_disk(const char *path, uint64_t expected_size)
{
    if (path == NULL || expected_size == 0) {
        return -1;
    }
    const int descriptor = open(
        path,
        O_RDWR | O_EXCL | O_EXLOCK | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
    if (descriptor < 0) {
        return -1;
    }
    struct stat identity = {0};
    uint32_t block_size = 0;
    uint64_t block_count = 0;
    const int valid = fstat(descriptor, &identity) == 0
        && S_ISCHR(identity.st_mode)
        && ioctl(descriptor, DKIOCGETBLOCKSIZE, &block_size) == 0
        && ioctl(descriptor, DKIOCGETBLOCKCOUNT, &block_count) == 0
        && block_size > 0
        && block_count <= UINT64_MAX / block_size
        && block_count * block_size == expected_size;
    if (!valid) {
        close(descriptor);
        return -1;
    }
    return descriptor;
}

int32_t bedrock_macos_probe_exclusive_disk(const char *path, uint64_t expected_size)
{
    const int32_t descriptor = bedrock_macos_open_validated_disk(path, expected_size);
    if (descriptor < 0) {
        return BRWriterRejected;
    }
    close(descriptor);
    return 0;
}

int32_t bedrock_macos_open_exclusive_disk(const char *path, uint64_t expected_size)
{
    return bedrock_macos_open_validated_disk(path, expected_size);
}

int32_t bedrock_macos_synchronize_disk(int32_t descriptor)
{
    if (descriptor < 0
        || fsync(descriptor) != 0
        || fcntl(descriptor, F_FULLFSYNC) != 0
        || ioctl(descriptor, DKIOCSYNCHRONIZECACHE) != 0) {
        return BRWriterRejected;
    }
    return 0;
}

int32_t bedrock_macos_eject_disk(int32_t descriptor)
{
    if (descriptor < 0 || ioctl(descriptor, DKIOCEJECT) != 0) {
        return BRWriterRejected;
    }
    return 0;
}

@protocol BRProgressProtocol
- (void)reportProgress:(NSData *)update;
@end

@protocol BRWriterProtocol
- (void)preflightRequest:(NSData *)request
    progress:(id<BRProgressProtocol>)progress
    withReply:(void (^)(NSInteger result))reply;
@end

static NSXPCInterface *bedrock_writer_interface(void)
{
    NSXPCInterface *writer = [NSXPCInterface interfaceWithProtocol:@protocol(BRWriterProtocol)];
    NSXPCInterface *progress = [NSXPCInterface interfaceWithProtocol:@protocol(BRProgressProtocol)];
    [writer setInterface:progress
        forSelector:@selector(preflightRequest:progress:withReply:)
        argumentIndex:1
        ofReply:NO];
    return writer;
}

static void bedrock_forward_progress(
    const uint8_t *bytes,
    uintptr_t length,
    void *context)
{
    if (bytes == NULL || length == 0 || context == NULL) {
        return;
    }
    id<BRProgressProtocol> progress = (__bridge id<BRProgressProtocol>)context;
    NSData *update = [NSData dataWithBytes:bytes length:length];
    [progress reportProgress:update];
}

@interface BRWriterService : NSObject <BRWriterProtocol>
@end

@implementation BRWriterService
- (void)preflightRequest:(NSData *)request
    progress:(id<BRProgressProtocol>)progress
    withReply:(void (^)(NSInteger result))reply
{
    const int32_t result = bedrock_macos_handle_writer_request(
        request.bytes,
        request.length,
        bedrock_forward_progress,
        (__bridge void *)progress);
    reply(result);
}
@end

@interface BRWriterListenerDelegate : NSObject <NSXPCListenerDelegate>
@end

@implementation BRWriterListenerDelegate
- (BOOL)listener:(NSXPCListener *)listener
    shouldAcceptNewConnection:(NSXPCConnection *)connection
{
    (void)listener;
    connection.exportedInterface = bedrock_writer_interface();
    connection.exportedObject = [BRWriterService new];
    [connection activate];
    return YES;
}
@end

int32_t bedrock_macos_run_writer_service(const char *client_requirement)
{
    @autoreleasepool {
        if (client_requirement == NULL) {
            return BRWriterRejected;
        }
        NSString *requirement = [NSString stringWithUTF8String:client_requirement];
        if (requirement == nil) {
            return BRWriterRejected;
        }
        @try {
            NSXPCListener *listener = [[NSXPCListener alloc] initWithMachServiceName:BRWriterServiceName];
            [listener setConnectionCodeSigningRequirement:requirement];
            BRWriterListenerDelegate *delegate = [BRWriterListenerDelegate new];
            listener.delegate = delegate;
            [listener activate];
            [[NSRunLoop currentRunLoop] run];
        } @catch (NSException *exception) {
            (void)exception;
            return BRWriterRejected;
        }
        return BRWriterRejected;
    }
}

@interface BRProgressReceiver : NSObject <BRProgressProtocol>
- (instancetype)initWithCallback:(BRProgressCallback)callback context:(void *)context;
- (void)invalidate;
@end

@implementation BRProgressReceiver {
    BRProgressCallback _callback;
    void *_context;
    NSLock *_lock;
}
- (instancetype)initWithCallback:(BRProgressCallback)callback context:(void *)context
{
    self = [super init];
    if (self != nil) {
        _callback = callback;
        _context = context;
        _lock = [NSLock new];
    }
    return self;
}
- (void)reportProgress:(NSData *)update
{
    [_lock lock];
    if (_callback != NULL && _context != NULL) {
        _callback(update.bytes, update.length, _context);
    }
    [_lock unlock];
}
- (void)invalidate
{
    [_lock lock];
    _callback = NULL;
    _context = NULL;
    [_lock unlock];
}
@end

int32_t bedrock_macos_send_writer_request(
    const uint8_t *bytes,
    uintptr_t length,
    const char *helper_requirement,
    BRProgressCallback progress_callback,
    void *progress_context)
{
    @autoreleasepool {
        if (bytes == NULL || length == 0 || helper_requirement == NULL) {
            return BRWriterRejected;
        }
        NSString *requirement = [NSString stringWithUTF8String:helper_requirement];
        if (requirement == nil) {
            return BRWriterRejected;
        }

        SMAppService *service = [SMAppService daemonServiceWithPlistName:BRWriterPlistName];
        if (service.status == SMAppServiceStatusNotRegistered) {
            NSError *registration_error = nil;
            if (![service registerAndReturnError:&registration_error]) {
                (void)registration_error;
                return BRWriterRegistrationFailed;
            }
        }
        if (service.status == SMAppServiceStatusRequiresApproval) {
            return BRWriterRequiresApproval;
        }
        if (service.status != SMAppServiceStatusEnabled) {
            return BRWriterRegistrationFailed;
        }

        __block int32_t result = BRWriterConnectionFailed;
        dispatch_semaphore_t completed = dispatch_semaphore_create(0);
        @try {
            NSXPCConnection *connection = [[NSXPCConnection alloc]
                initWithMachServiceName:BRWriterServiceName
                options:NSXPCConnectionPrivileged];
            connection.remoteObjectInterface = bedrock_writer_interface();
            [connection setCodeSigningRequirement:requirement];
            [connection activate];
            id<BRWriterProtocol> proxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
                (void)error;
                dispatch_semaphore_signal(completed);
            }];
            NSData *request = [NSData dataWithBytes:bytes length:length];
            BRProgressReceiver *progress = [[BRProgressReceiver alloc]
                initWithCallback:progress_callback
                context:progress_context];
            [proxy preflightRequest:request progress:progress withReply:^(NSInteger reply) {
                result = (int32_t)reply;
                dispatch_semaphore_signal(completed);
            }];
#ifdef BEDROCK_PHYSICAL_WRITER
            const int64_t timeout_seconds = 24 * 60 * 60;
#else
            const int64_t timeout_seconds = 120;
#endif
            const dispatch_time_t deadline = dispatch_time(
                DISPATCH_TIME_NOW, timeout_seconds * NSEC_PER_SEC);
            if (dispatch_semaphore_wait(completed, deadline) != 0) {
                result = BRWriterConnectionFailed;
            }
            [progress invalidate];
            [connection invalidate];
        } @catch (NSException *exception) {
            (void)exception;
            return BRWriterConnectionFailed;
        }
        return result;
    }
}
