#import <Foundation/Foundation.h>
#import <ServiceManagement/ServiceManagement.h>
#import <dispatch/dispatch.h>
#include <stdint.h>

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
