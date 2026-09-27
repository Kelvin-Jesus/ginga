#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Errors from the USB accessory shim (IOReturn codes are carried in `NSUnderlyingErrorKey`).
extern NSErrorDomain const GingaUSBErrorDomain;

typedef NS_ERROR_ENUM(GingaUSBErrorDomain, GingaUSBError) {
    GingaUSBErrorDeviceNotFound = 1,
    GingaUSBErrorOpenFailed = 2,
    GingaUSBErrorRequestFailed = 3,
    GingaUSBErrorNoAccessoryInterface = 4,
    GingaUSBErrorNoBulkEndpoints = 5,
    GingaUSBErrorTransferFailed = 6,
    GingaUSBErrorClosed = 7,
};

/// A bulk transfer that ends exactly on a packet boundary must be followed by a zero-length packet.
static inline BOOL GingaNeedsZeroLengthPacket(NSUInteger length, NSUInteger maxPacketSize) {
    return length > 0 && maxPacketSize > 0 && length % maxPacketSize == 0;
}

/// A USB device opened *without* exclusive access (other clients such as adb keep working), for
/// vendor control requests on endpoint 0 — the Android Open Accessory handshake.
@interface GingaUSBDevice : NSObject

+ (nullable instancetype)openWithRegistryEntryID:(uint64_t)entryID error:(NSError **)error;

/// Device-to-host vendor request (bmRequestType 0xC0).
- (nullable NSData *)vendorRequestInWithRequest:(uint8_t)request
                                          value:(uint16_t)value
                                          index:(uint16_t)index
                                         length:(uint16_t)length
                                          error:(NSError **)error;

/// Host-to-device vendor request (bmRequestType 0x40).
- (BOOL)vendorRequestOutWithRequest:(uint8_t)request
                              value:(uint16_t)value
                              index:(uint16_t)index
                               data:(nullable NSData *)data
                              error:(NSError **)error;

- (void)close;

@end

/// The bulk IN/OUT pipes of an Android device in accessory mode (interface class FF/FF): a
/// reliable byte stream. Callbacks run on the queue given at open.
@interface GingaAccessoryLink : NSObject

+ (nullable instancetype)openWithDeviceRegistryEntryID:(uint64_t)entryID
                                                 queue:(dispatch_queue_t)queue
                                                 error:(NSError **)error;

@property (nonatomic, readonly) NSUInteger maxPacketSize;

/// Keeps reads pending until closed. `onClose` fires once: nil error = device went away.
- (void)startReadingWithHandler:(void (^)(NSData *data))onData
                   closeHandler:(void (^)(NSError *_Nullable error))onClose;

/// Queues a bulk OUT transfer, followed by a zero-length packet when the length is a multiple of
/// the max packet size (the device's read would otherwise wait for more data).
- (void)writeData:(NSData *)data completion:(void (^)(NSError *_Nullable error))completion;

/// Aborts transfers and releases the interface. Idempotent.
- (void)close;

@end

NS_ASSUME_NONNULL_END
