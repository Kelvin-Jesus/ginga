// Ginga — the single boundary around Apple's private CGVirtualDisplay API.
//
// Nothing else in the project may reference CGVirtualDisplay* classes. This shim:
//   • never links against the private classes (they are looked up by name at runtime),
//   • verifies every class, selector and type encoding it uses before the first message,
//   • converts Objective-C exceptions and nil/0 results into NSError instead of crashing.
//
// The expected interface was dumped from the Objective-C runtime on macOS 26.6.2 (25G83);
// see docs/virtual-display-backend.md.

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const GingaPrivateDisplayErrorDomain;

typedef NS_ERROR_ENUM(GingaPrivateDisplayErrorDomain, GingaPrivateDisplayError) {
    /// Required classes/selectors are missing or have unexpected type encodings.
    GingaPrivateDisplayErrorUnavailable = 1,
    /// -initWithDescriptor: returned nil or a display ID of 0.
    GingaPrivateDisplayErrorCreationFailed = 2,
    /// A mode was rejected or -applySettings: returned NO.
    GingaPrivateDisplayErrorSettingsRejected = 3,
    /// The private API raised an Objective-C exception.
    GingaPrivateDisplayErrorException = 4,
    /// The display was already destroyed.
    GingaPrivateDisplayErrorInvalidated = 5,
};

/// Resolves a private class name to a class. Production uses NSClassFromString; tests inject fakes.
typedef Class _Nullable (^GingaClassResolver)(NSString *className);

/// Result of verifying the runtime's private API surface against what the shim expects.
@interface GingaPrivateAPIReport : NSObject
@property (nonatomic, readonly, getter=isUsable) BOOL usable;
/// Blocking problems (missing class/selector, incompatible signature). Empty when usable.
@property (nonatomic, readonly, copy) NSArray<NSString *> *problems;
/// Optional capabilities that are absent (e.g. colour primaries). Informational only.
@property (nonatomic, readonly, copy) NSArray<NSString *> *missingOptional;
/// One line per verified requirement, for diagnostics.
@property (nonatomic, readonly, copy) NSArray<NSString *> *checks;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface GingaPrivateAPIChecker : NSObject
/// Checks the real runtime (NSClassFromString).
+ (GingaPrivateAPIReport *)checkRuntime;
+ (GingaPrivateAPIReport *)checkWithClassResolver:(GingaClassResolver)resolver;
/// Strips stack offsets from a method type encoding: "B24@0:8@16" → "B@:@".
+ (NSString *)normalizedTypeEncoding:(NSString *)encoding;
/// Describes every property and method of the private classes as the runtime reports them.
+ (NSArray<NSString *> *)runtimeInterfaceDump;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface GingaVirtualDisplayModeSpec : NSObject
- (instancetype)initWithWidth:(uint32_t)width height:(uint32_t)height refreshRate:(double)refreshRate NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
/// Logical size in points (the display renders at 2× when HiDPI is enabled).
@property (nonatomic, readonly) uint32_t width;
@property (nonatomic, readonly) uint32_t height;
@property (nonatomic, readonly) double refreshRate;
@end

@interface GingaVirtualDisplaySpec : NSObject
@property (nonatomic, copy) NSString *name;
/// Must be non-zero: macOS 14+ refuses displays with vendorID 0.
@property (nonatomic) uint32_t vendorID;
@property (nonatomic) uint32_t productID;
@property (nonatomic) uint32_t serialNumber;
@property (nonatomic) uint32_t maxPixelsWide;
@property (nonatomic) uint32_t maxPixelsHigh;
@property (nonatomic) CGSize sizeInMillimeters;
/// When YES the chromaticities below are applied (if the runtime supports them).
@property (nonatomic) BOOL hasColorPrimaries;
@property (nonatomic) CGPoint redPrimary;
@property (nonatomic) CGPoint greenPrimary;
@property (nonatomic) CGPoint bluePrimary;
@property (nonatomic) CGPoint whitePoint;
@end

/// Owns exactly one private CGVirtualDisplay; releasing it (or -invalidate) removes the display.
/// Main thread only. The termination handler is invoked on the main queue.
@interface GingaPrivateVirtualDisplay : NSObject

- (nullable instancetype)initWithSpec:(GingaVirtualDisplaySpec *)spec
                                modes:(NSArray<GingaVirtualDisplayModeSpec *> *)modes
                                hiDPI:(BOOL)hiDPI
                   terminationHandler:(dispatch_block_t)terminationHandler
                                error:(NSError **)error;

- (nullable instancetype)initWithSpec:(GingaVirtualDisplaySpec *)spec
                                modes:(NSArray<GingaVirtualDisplayModeSpec *> *)modes
                                hiDPI:(BOOL)hiDPI
                   terminationHandler:(dispatch_block_t)terminationHandler
                        classResolver:(GingaClassResolver)classResolver
                                error:(NSError **)error NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) CGDirectDisplayID displayID;
@property (nonatomic, readonly, getter=isValid) BOOL valid;

/// Replaces the advertised modes (preferred first) without recreating the display.
- (BOOL)applyModes:(NSArray<GingaVirtualDisplayModeSpec *> *)modes hiDPI:(BOOL)hiDPI error:(NSError **)error;

/// Releases the private display object, which removes the display. Idempotent.
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
