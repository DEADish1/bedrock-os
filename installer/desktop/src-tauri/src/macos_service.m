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

extern int32_t bedrock_macos_handle_writer_request(const uint8_t *bytes, uintptr_t length);

int32_t bedrock_macos_probe_exclusive_disk(const char *path, uint64_t expected_size)
{
    if (path == NULL || expected_size == 0) {
        return BRWriterRejected;
    }
    const int descriptor = open(
        path,
        O_RDWR | O_EXCL | O_EXLOCK | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
    if (descriptor < 0) {
        return BRWriterRejected;
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
    close(descriptor);
    return valid ? 0 : BRWriterRejected;
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

@protocol BRWriterProtocol
- (void)preflightRequest:(NSData *)request withReply:(void (^)(NSInteger result))reply;
@end

@interface BRWriterService : NSObject <BRWriterProtocol>
@end

@implementation BRWriterService
- (void)preflightRequest:(NSData *)request withReply:(void (^)(NSInteger result))reply
{
    const int32_t result = bedrock_macos_handle_writer_request(request.bytes, request.length);
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
    connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(BRWriterProtocol)];
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

int32_t bedrock_macos_send_writer_request(
    const uint8_t *bytes,
    uintptr_t length,
    const char *helper_requirement)
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
            connection.remoteObjectInterface =
                [NSXPCInterface interfaceWithProtocol:@protocol(BRWriterProtocol)];
            [connection setCodeSigningRequirement:requirement];
            [connection activate];
            id<BRWriterProtocol> proxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
                (void)error;
                dispatch_semaphore_signal(completed);
            }];
            NSData *request = [NSData dataWithBytes:bytes length:length];
            [proxy preflightRequest:request withReply:^(NSInteger reply) {
                result = (int32_t)reply;
                dispatch_semaphore_signal(completed);
            }];
            const dispatch_time_t deadline = dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC);
            if (dispatch_semaphore_wait(completed, deadline) != 0) {
                result = BRWriterConnectionFailed;
            }
            [connection invalidate];
        } @catch (NSException *exception) {
            (void)exception;
            return BRWriterConnectionFailed;
        }
        return result;
    }
}
