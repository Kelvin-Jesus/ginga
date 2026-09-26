#import "T2MShimFakes.h"

@implementation T2MFakeVirtualDisplayDescriptor
@end

@implementation T2MFakeLegacyDescriptor
@end

@implementation T2MFakeVirtualDisplayMode

- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)refreshRate {
    if ((self = [super init])) {
        _width = width;
        _height = height;
        _refreshRate = refreshRate;
    }
    return self;
}

@end

@implementation T2MFakeVirtualDisplayModeWrongTypes

- (instancetype)initWithWidth:(NSUInteger)__unused width height:(NSUInteger)__unused height refreshRate:(double)__unused refreshRate {
    return [super init];
}

@end

@implementation T2MFakeVirtualDisplaySettings
@end

static unsigned int gNextDisplayID = 42;
static BOOL gRaiseOnInit = NO;
static BOOL gRaiseOnApply = NO;
static BOOL gApplyResult = YES;
static NSInteger gLiveInstances = 0;
static NSInteger gInstancesCreated = 0;
static __weak T2MFakeVirtualDisplay *gLastInstance = nil;

@implementation T2MFakeVirtualDisplay {
    NSMutableArray *_appliedSettings;
}

+ (unsigned int)nextDisplayID { return gNextDisplayID; }
+ (void)setNextDisplayID:(unsigned int)value { gNextDisplayID = value; }
+ (BOOL)raiseOnInit { return gRaiseOnInit; }
+ (void)setRaiseOnInit:(BOOL)value { gRaiseOnInit = value; }
+ (BOOL)raiseOnApply { return gRaiseOnApply; }
+ (void)setRaiseOnApply:(BOOL)value { gRaiseOnApply = value; }
+ (BOOL)applyResult { return gApplyResult; }
+ (void)setApplyResult:(BOOL)value { gApplyResult = value; }
+ (NSInteger)liveInstances { return gLiveInstances; }
+ (NSInteger)instancesCreated { return gInstancesCreated; }
+ (nullable T2MFakeVirtualDisplay *)lastInstance { return gLastInstance; }

+ (void)reset {
    gNextDisplayID = 42;
    gRaiseOnInit = NO;
    gRaiseOnApply = NO;
    gApplyResult = YES;
    gInstancesCreated = 0;
}

- (instancetype)initWithDescriptor:(id)descriptor {
    if (gRaiseOnInit) {
        [NSException raise:NSInternalInconsistencyException format:@"fake WindowServer refused the descriptor"];
    }
    if ((self = [super init])) {
        _descriptor = descriptor;
        _displayID = gNextDisplayID;
        _appliedSettings = [NSMutableArray array];
        gLiveInstances += 1;
        gInstancesCreated += 1;
        gLastInstance = self;
    }
    return self;
}

- (void)dealloc {
    gLiveInstances -= 1;
}

- (BOOL)applySettings:(id)settings {
    if (gRaiseOnApply) {
        [NSException raise:NSInvalidArgumentException format:@"fake WindowServer rejected the settings"];
    }
    [_appliedSettings addObject:settings];
    return gApplyResult;
}

- (NSArray *)appliedSettings {
    return [_appliedSettings copy];
}

- (void)simulateTermination {
    void (^handler)(id, id) = [_descriptor valueForKey:@"terminationHandler"];
    dispatch_queue_t queue = [_descriptor respondsToSelector:@selector(queue)] ? [_descriptor valueForKey:@"queue"] : dispatch_get_main_queue();
    if (handler) {
        dispatch_async(queue ?: dispatch_get_main_queue(), ^{
            handler(nil, self);
        });
    }
}

@end

@implementation T2MFakeVirtualDisplayWithoutApply

- (instancetype)initWithDescriptor:(id)__unused descriptor {
    if ((self = [super init])) {
        _displayID = 7;
    }
    return self;
}

@end
