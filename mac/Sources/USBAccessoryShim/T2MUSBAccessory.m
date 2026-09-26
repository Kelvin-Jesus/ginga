#import "T2MUSBAccessory.h"

#import <IOKit/IOKitLib.h>
#import <IOKit/IOMessage.h>
#import <IOUSBHost/IOUSBHost.h>

NSErrorDomain const T2MUSBErrorDomain = @"dev.tab2mac.usb";

static NSError *T2MError(T2MUSBError code, NSString *message, NSError *_Nullable underlying) {
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
    if (underlying) { info[NSUnderlyingErrorKey] = underlying; }
    return [NSError errorWithDomain:T2MUSBErrorDomain code:code userInfo:info];
}

static NSError *T2MIOReturnError(T2MUSBError code, NSString *message, IOReturn status) {
    NSError *underlying = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
    return T2MError(code, [NSString stringWithFormat:@"%@ (IOReturn 0x%08x)", message, status], underlying);
}

static io_service_t T2MServiceForEntryID(uint64_t entryID) {
    return IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(entryID));
}

static NSNumber *_Nullable T2MIntegerProperty(io_registry_entry_t entry, CFStringRef key) {
    id value = CFBridgingRelease(IORegistryEntryCreateCFProperty(entry, key, kCFAllocatorDefault, 0));
    return [value isKindOfClass:[NSNumber class]] ? value : nil;
}

#pragma mark - Device (control requests)

@implementation T2MUSBDevice {
    IOUSBHostDevice *_device;
    dispatch_queue_t _queue;
}

+ (instancetype)openWithRegistryEntryID:(uint64_t)entryID error:(NSError **)error {
    io_service_t service = T2MServiceForEntryID(entryID);
    if (!service) {
        if (error) { *error = T2MError(T2MUSBErrorDeviceNotFound, @"USB device is gone", nil); }
        return nil;
    }
    dispatch_queue_t queue = dispatch_queue_create("dev.tab2mac.usb.device", DISPATCH_QUEUE_SERIAL);
    NSError *openError = nil;
    // No capture, no seize: adb and MTP keep their interfaces.
    IOUSBHostDevice *device = [[IOUSBHostDevice alloc] initWithIOService:service
                                                                options:IOUSBHostObjectInitOptionsNone
                                                                  queue:queue
                                                                  error:&openError
                                                        interestHandler:nil];
    IOObjectRelease(service);
    if (!device) {
        if (error) { *error = T2MError(T2MUSBErrorOpenFailed, @"could not open the USB device", openError); }
        return nil;
    }
    T2MUSBDevice *wrapper = [[T2MUSBDevice alloc] init];
    wrapper->_device = device;
    wrapper->_queue = queue;
    return wrapper;
}

- (NSData *)vendorRequestInWithRequest:(uint8_t)request value:(uint16_t)value index:(uint16_t)index length:(uint16_t)length error:(NSError **)error {
    IOUSBDeviceRequest setup = { .bmRequestType = 0xC0, .bRequest = request, .wValue = value, .wIndex = index, .wLength = length };
    NSMutableData *data = [NSMutableData dataWithLength:length];
    NSUInteger transferred = 0;
    NSError *requestError = nil;
    if (![_device sendDeviceRequest:setup data:data bytesTransferred:&transferred completionTimeout:1.0 error:&requestError]) {
        if (error) { *error = T2MError(T2MUSBErrorRequestFailed, [NSString stringWithFormat:@"vendor request %u failed", request], requestError); }
        return nil;
    }
    data.length = transferred;
    return data;
}

- (BOOL)vendorRequestOutWithRequest:(uint8_t)request value:(uint16_t)value index:(uint16_t)index data:(NSData *)data error:(NSError **)error {
    IOUSBDeviceRequest setup = { .bmRequestType = 0x40, .bRequest = request, .wValue = value, .wIndex = index, .wLength = (uint16_t)data.length };
    NSMutableData *payload = data.length > 0 ? [data mutableCopy] : nil;
    NSUInteger transferred = 0;
    NSError *requestError = nil;
    if (![_device sendDeviceRequest:setup data:payload bytesTransferred:&transferred completionTimeout:1.0 error:&requestError]) {
        if (error) { *error = T2MError(T2MUSBErrorRequestFailed, [NSString stringWithFormat:@"vendor request %u failed", request], requestError); }
        return NO;
    }
    return YES;
}

- (void)close {
    [_device destroy];
    _device = nil;
}

- (void)dealloc {
    [_device destroy];
}

@end

#pragma mark - Accessory link (bulk pipes)

/// Reads kept in flight. f_accessory serves host→device data 16 KB at a time; the other direction
/// is ordinary bulk IN, where two 64 KB requests keep the pipe busy without copying per packet.
static const NSUInteger T2MReadSize = 64 * 1024;
static const NSUInteger T2MReadsInFlight = 2;

@implementation T2MAccessoryLink {
    IOUSBHostInterface *_interface;
    IOUSBHostPipe *_inPipe;
    IOUSBHostPipe *_outPipe;
    dispatch_queue_t _queue;
    void (^_onData)(NSData *);
    void (^_onClose)(NSError *_Nullable);
    BOOL _closed;
}

+ (instancetype)openWithDeviceRegistryEntryID:(uint64_t)entryID queue:(dispatch_queue_t)queue error:(NSError **)error {
    io_service_t device = T2MServiceForEntryID(entryID);
    if (!device) {
        if (error) { *error = T2MError(T2MUSBErrorDeviceNotFound, @"USB device is gone", nil); }
        return nil;
    }
    // The accessory interface (class FF, subclass FF) among the device's interfaces; in 18D1:2D01
    // interface 1 is adb (FF/42/01), which adb keeps.
    io_service_t interfaceService = 0;
    io_iterator_t iterator = 0;
    if (IORegistryEntryCreateIterator(device, kIOServicePlane, kIORegistryIterateRecursively, &iterator) == KERN_SUCCESS) {
        io_registry_entry_t entry;
        while ((entry = IOIteratorNext(iterator))) {
            if (!interfaceService && IOObjectConformsTo(entry, "IOUSBHostInterface")) {
                NSNumber *interfaceClass = T2MIntegerProperty(entry, CFSTR("bInterfaceClass"));
                NSNumber *interfaceSubclass = T2MIntegerProperty(entry, CFSTR("bInterfaceSubClass"));
                if (interfaceClass.intValue == 0xFF && interfaceSubclass.intValue == 0xFF) {
                    interfaceService = entry;
                    continue;
                }
            }
            IOObjectRelease(entry);
        }
        IOObjectRelease(iterator);
    }
    IOObjectRelease(device);
    if (!interfaceService) {
        if (error) { *error = T2MError(T2MUSBErrorNoAccessoryInterface, @"no accessory interface (FF/FF) on the device", nil); }
        return nil;
    }

    T2MAccessoryLink *link = [[T2MAccessoryLink alloc] init];
    link->_queue = queue;
    __weak T2MAccessoryLink *weakLink = link;
    NSError *openError = nil;
    IOUSBHostInterface *interface = [[IOUSBHostInterface alloc] initWithIOService:interfaceService
                                                                          options:IOUSBHostObjectInitOptionsNone
                                                                            queue:queue
                                                                            error:&openError
                                                                  interestHandler:^(IOUSBHostObject *object, uint32_t messageType, void *argument) {
        if (messageType == kIOMessageServiceIsTerminated) { [weakLink finishWithError:nil]; }
    }];
    IOObjectRelease(interfaceService);
    if (!interface) {
        if (error) { *error = T2MError(T2MUSBErrorOpenFailed, @"could not open the accessory interface", openError); }
        return nil;
    }

    const IOUSBConfigurationDescriptor *configuration = interface.configurationDescriptor;
    const IOUSBInterfaceDescriptor *interfaceDescriptor = interface.interfaceDescriptor;
    const IOUSBEndpointDescriptor *endpoint = NULL;
    uint8_t inAddress = 0, outAddress = 0;
    uint16_t maxPacket = 512;
    while (configuration && interfaceDescriptor
           && (endpoint = IOUSBGetNextEndpointDescriptor(configuration, interfaceDescriptor, (const IOUSBDescriptorHeader *)endpoint))) {
        if (IOUSBGetEndpointType(endpoint) != kIOUSBEndpointTypeBulk) { continue; }
        uint16_t size = OSSwapLittleToHostInt16(endpoint->wMaxPacketSize) & 0x7FF;
        if (IOUSBGetEndpointDirection(endpoint) == kIOUSBEndpointDirectionIn) {
            if (!inAddress) { inAddress = endpoint->bEndpointAddress; }
        } else if (!outAddress) {
            outAddress = endpoint->bEndpointAddress;
            if (size > 0) { maxPacket = size; }
        }
    }
    if (!inAddress || !outAddress) {
        [interface destroy];
        if (error) { *error = T2MError(T2MUSBErrorNoBulkEndpoints, @"accessory interface has no bulk IN/OUT pair", nil); }
        return nil;
    }
    NSError *pipeError = nil;
    IOUSBHostPipe *inPipe = [interface copyPipeWithAddress:inAddress error:&pipeError];
    IOUSBHostPipe *outPipe = inPipe ? [interface copyPipeWithAddress:outAddress error:&pipeError] : nil;
    if (!inPipe || !outPipe) {
        [interface destroy];
        if (error) { *error = T2MError(T2MUSBErrorOpenFailed, @"could not open the bulk pipes", pipeError); }
        return nil;
    }
    link->_interface = interface;
    link->_inPipe = inPipe;
    link->_outPipe = outPipe;
    link->_maxPacketSize = maxPacket;
    return link;
}

- (void)startReadingWithHandler:(void (^)(NSData *))onData closeHandler:(void (^)(NSError *_Nullable))onClose {
    dispatch_async(_queue, ^{
        self->_onData = [onData copy];
        self->_onClose = [onClose copy];
        for (NSUInteger i = 0; i < T2MReadsInFlight; i++) {
            [self enqueueReadWithBuffer:[NSMutableData dataWithLength:T2MReadSize]];
        }
    });
}

- (void)enqueueReadWithBuffer:(NSMutableData *)buffer {
    if (_closed) { return; }
    buffer.length = T2MReadSize;
    __weak T2MAccessoryLink *weakSelf = self;
    NSError *error = nil;
    BOOL queued = [_inPipe enqueueIORequestWithData:buffer completionTimeout:0 error:&error completionHandler:^(IOReturn status, NSUInteger bytesTransferred) {
        T2MAccessoryLink *link = weakSelf;
        if (!link || link->_closed) { return; }
        if (status != kIOReturnSuccess) {
            [link finishWithError:status == kIOReturnAborted || status == kIOReturnNotResponding || status == kIOReturnNoDevice
                ? nil : T2MIOReturnError(T2MUSBErrorTransferFailed, @"bulk IN failed", status)];
            return;
        }
        if (bytesTransferred > 0 && link->_onData) {
            link->_onData([NSData dataWithBytes:buffer.bytes length:bytesTransferred]);
        }
        [link enqueueReadWithBuffer:buffer];
    }];
    if (!queued) { [self finishWithError:T2MError(T2MUSBErrorTransferFailed, @"could not queue a bulk IN read", error)]; }
}

- (void)writeData:(NSData *)data completion:(void (^)(NSError *_Nullable))completion {
    dispatch_async(_queue, ^{
        if (self->_closed) {
            completion(T2MError(T2MUSBErrorClosed, @"link closed", nil));
            return;
        }
        NSMutableData *payload = [data mutableCopy];
        NSError *error = nil;
        BOOL queued = [self->_outPipe enqueueIORequestWithData:payload completionTimeout:0 error:&error completionHandler:^(IOReturn status, NSUInteger bytesTransferred) {
            completion(status == kIOReturnSuccess ? nil : T2MIOReturnError(T2MUSBErrorTransferFailed, @"bulk OUT failed", status));
        }];
        if (!queued) {
            completion(T2MError(T2MUSBErrorTransferFailed, @"could not queue a bulk OUT write", error));
            return;
        }
        // A transfer that ends exactly on a packet boundary needs a zero-length packet, or the
        // device's read keeps waiting for more data.
        if (T2MNeedsZeroLengthPacket(data.length, self->_maxPacketSize)) {
            [self->_outPipe enqueueIORequestWithData:[NSMutableData data] completionTimeout:0 error:nil completionHandler:^(IOReturn status, NSUInteger bytesTransferred) {}];
        }
    });
}

- (void)finishWithError:(NSError *_Nullable)error {
    dispatch_async(_queue, ^{
        if (self->_closed) { return; }
        self->_closed = YES;
        [self->_inPipe abortWithOption:IOUSBHostAbortOptionAsynchronous error:nil];
        [self->_outPipe abortWithOption:IOUSBHostAbortOptionAsynchronous error:nil];
        [self->_interface destroy];
        void (^onClose)(NSError *_Nullable) = self->_onClose;
        self->_onClose = nil;
        self->_onData = nil;
        if (onClose) { onClose(error); }
    });
}

- (void)close {
    [self finishWithError:nil];
}

@end
