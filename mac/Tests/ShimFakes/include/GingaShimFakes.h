// Test doubles that mimic the private CGVirtualDisplay classes' selectors and type encodings
// exactly, so the shim's verification and error handling can be exercised without WindowServer.

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GingaFakeVirtualDisplayDescriptor : NSObject
@property (nonatomic, copy, nullable) NSString *name;
@property (nonatomic) unsigned int maxPixelsWide;
@property (nonatomic) unsigned int maxPixelsHigh;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) unsigned int vendorID;
@property (nonatomic) unsigned int productID;
@property (nonatomic) unsigned int serialNumber;
@property (nonatomic, strong, nullable) dispatch_queue_t queue;
@property (nonatomic, copy, nullable) void (^terminationHandler)(id _Nullable, id _Nullable);
@property (nonatomic) CGPoint redPrimary;
@property (nonatomic) CGPoint greenPrimary;
@property (nonatomic) CGPoint bluePrimary;
@property (nonatomic) CGPoint whitePoint;
@end

/// Older naming (`serialNum`, `dispatchQueue`) and no colour primaries.
@interface GingaFakeLegacyDescriptor : NSObject
@property (nonatomic, copy, nullable) NSString *name;
@property (nonatomic) unsigned int maxPixelsWide;
@property (nonatomic) unsigned int maxPixelsHigh;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) unsigned int vendorID;
@property (nonatomic) unsigned int productID;
@property (nonatomic) unsigned int serialNum;
@property (nonatomic, strong, nullable) dispatch_queue_t dispatchQueue;
@property (nonatomic, copy, nullable) void (^terminationHandler)(id _Nullable, id _Nullable);
@end

@interface GingaFakeVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)refreshRate;
@property (nonatomic, readonly) unsigned int width;
@property (nonatomic, readonly) unsigned int height;
@property (nonatomic, readonly) double refreshRate;
@end

/// Same selector as the real mode initialiser but with NSUInteger sizes (incompatible encoding).
@interface GingaFakeVirtualDisplayModeWrongTypes : NSObject
- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(double)refreshRate;
@end

@interface GingaFakeVirtualDisplaySettings : NSObject
@property (nonatomic, strong, nullable) NSArray *modes;
@property (nonatomic) unsigned int hiDPI;
@end

/// Behaviour is configured through class properties; call +reset between tests.
@interface GingaFakeVirtualDisplay : NSObject
@property (class, nonatomic) unsigned int nextDisplayID;
@property (class, nonatomic) BOOL raiseOnInit;
@property (class, nonatomic) BOOL raiseOnApply;
@property (class, nonatomic) BOOL applyResult;
@property (class, nonatomic, readonly) NSInteger liveInstances;
@property (class, nonatomic, readonly) NSInteger instancesCreated;
@property (class, nonatomic, readonly, nullable) GingaFakeVirtualDisplay *lastInstance;
+ (void)reset;

- (instancetype)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
@property (nonatomic, readonly) unsigned int displayID;
@property (nonatomic, readonly, nullable) id descriptor;
@property (nonatomic, readonly) NSArray *appliedSettings;
/// Invokes the descriptor's termination handler like WindowServer would.
- (void)simulateTermination;
@end

/// A display class without -applySettings: (missing selector).
@interface GingaFakeVirtualDisplayWithoutApply : NSObject
- (instancetype)initWithDescriptor:(id)descriptor;
@property (nonatomic, readonly) unsigned int displayID;
@end

NS_ASSUME_NONNULL_END
