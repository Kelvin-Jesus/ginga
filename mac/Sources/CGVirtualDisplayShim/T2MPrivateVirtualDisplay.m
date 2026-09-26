#import "T2MPrivateVirtualDisplay.h"

#import <objc/runtime.h>

NSErrorDomain const T2MPrivateDisplayErrorDomain = @"dev.tab2mac.private-virtual-display";

#pragma mark - Private interface (messaging only; never used as class references)
//
// Declared as protocols so that no `_OBJC_CLASS_$_CGVirtualDisplay*` symbol is referenced:
// the binary loads even if Apple removes the classes, and the checker below decides whether
// the shim may send any of these messages. Signatures match the runtime type encodings.

@protocol T2MPrivateCGVirtualDisplayDescriptor <NSObject>
- (instancetype)init;
- (void)setName:(NSString *)name;
- (void)setMaxPixelsWide:(unsigned int)value;
- (void)setMaxPixelsHigh:(unsigned int)value;
- (void)setSizeInMillimeters:(CGSize)value;
- (void)setVendorID:(unsigned int)value;
- (void)setProductID:(unsigned int)value;
- (void)setTerminationHandler:(void (^)(id _Nullable, id _Nullable))handler;
@optional
- (void)setSerialNumber:(unsigned int)value;
- (void)setSerialNum:(unsigned int)value;
- (void)setQueue:(dispatch_queue_t)queue;
- (void)setDispatchQueue:(dispatch_queue_t)queue;
- (void)setRedPrimary:(CGPoint)value;
- (void)setGreenPrimary:(CGPoint)value;
- (void)setBluePrimary:(CGPoint)value;
- (void)setWhitePoint:(CGPoint)value;
@end

@protocol T2MPrivateCGVirtualDisplayMode <NSObject>
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)refreshRate;
@end

@protocol T2MPrivateCGVirtualDisplaySettings <NSObject>
- (instancetype)init;
- (void)setModes:(NSArray *)modes;
- (void)setHiDPI:(unsigned int)hiDPI;
@end

@protocol T2MPrivateCGVirtualDisplay <NSObject>
- (instancetype)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
- (unsigned int)displayID;
@end

static NSString *const kDescriptorClass = @"CGVirtualDisplayDescriptor";
static NSString *const kModeClass = @"CGVirtualDisplayMode";
static NSString *const kSettingsClass = @"CGVirtualDisplaySettings";
static NSString *const kDisplayClass = @"CGVirtualDisplay";

#pragma mark - Requirements

typedef struct {
    const char *className;
    const char *selectors;  // "|"-separated alternatives; the first one present is checked
    const char *types;      // "|"-separated acceptable normalized encodings
    BOOL optional;
} T2MRequirement;

// Every message the shim sends, with the encodings observed on macOS 26.6.2 (arm64).
// BOOL is 'B' on arm64 and 'c' on x86_64, hence both for -applySettings:.
static const T2MRequirement kRequirements[] = {
    {"CGVirtualDisplayDescriptor", "init", "@@:", NO},
    {"CGVirtualDisplayDescriptor", "setName:", "v@:@", NO},
    {"CGVirtualDisplayDescriptor", "setMaxPixelsWide:", "v@:I", NO},
    {"CGVirtualDisplayDescriptor", "setMaxPixelsHigh:", "v@:I", NO},
    {"CGVirtualDisplayDescriptor", "setSizeInMillimeters:", "v@:{CGSize=dd}", NO},
    {"CGVirtualDisplayDescriptor", "setVendorID:", "v@:I", NO},
    {"CGVirtualDisplayDescriptor", "setProductID:", "v@:I", NO},
    {"CGVirtualDisplayDescriptor", "setSerialNumber:|setSerialNum:", "v@:I", NO},
    {"CGVirtualDisplayDescriptor", "setQueue:|setDispatchQueue:", "v@:@", NO},
    {"CGVirtualDisplayDescriptor", "setTerminationHandler:", "v@:@?", NO},
    {"CGVirtualDisplayDescriptor", "setRedPrimary:", "v@:{CGPoint=dd}", YES},
    {"CGVirtualDisplayDescriptor", "setGreenPrimary:", "v@:{CGPoint=dd}", YES},
    {"CGVirtualDisplayDescriptor", "setBluePrimary:", "v@:{CGPoint=dd}", YES},
    {"CGVirtualDisplayDescriptor", "setWhitePoint:", "v@:{CGPoint=dd}", YES},
    {"CGVirtualDisplayMode", "initWithWidth:height:refreshRate:", "@@:IId", NO},
    {"CGVirtualDisplaySettings", "init", "@@:", NO},
    {"CGVirtualDisplaySettings", "setModes:", "v@:@", NO},
    {"CGVirtualDisplaySettings", "setHiDPI:", "v@:I", NO},
    {"CGVirtualDisplay", "initWithDescriptor:", "@@:@", NO},
    {"CGVirtualDisplay", "applySettings:", "B@:@|c@:@", NO},
    {"CGVirtualDisplay", "displayID", "I@:", NO},
};

static NSError *T2MMakeError(T2MPrivateDisplayError code, NSString *description) {
    return [NSError errorWithDomain:T2MPrivateDisplayErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

static void T2MSetError(NSError **error, T2MPrivateDisplayError code, NSString *description) {
    if (error) *error = T2MMakeError(code, description);
}

static NSString *T2MDescribeException(NSException *exception) {
    return [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason ?: @"(no reason)"];
}

#pragma mark - Report & checker

@implementation T2MPrivateAPIReport

- (instancetype)initWithProblems:(NSArray<NSString *> *)problems
                 missingOptional:(NSArray<NSString *> *)missingOptional
                          checks:(NSArray<NSString *> *)checks {
    if ((self = [super init])) {
        _problems = [problems copy];
        _missingOptional = [missingOptional copy];
        _checks = [checks copy];
        _usable = problems.count == 0;
    }
    return self;
}

@end

@implementation T2MPrivateAPIChecker

+ (T2MPrivateAPIReport *)checkRuntime {
    return [self checkWithClassResolver:^Class _Nullable(NSString *name) { return NSClassFromString(name); }];
}

+ (T2MPrivateAPIReport *)checkWithClassResolver:(T2MClassResolver)resolver {
    NSMutableArray<NSString *> *problems = [NSMutableArray array];
    NSMutableArray<NSString *> *missingOptional = [NSMutableArray array];
    NSMutableArray<NSString *> *checks = [NSMutableArray array];
    NSMutableSet<NSString *> *missingClasses = [NSMutableSet set];

    for (size_t i = 0; i < sizeof(kRequirements) / sizeof(kRequirements[0]); i++) {
        T2MRequirement requirement = kRequirements[i];
        NSString *className = @(requirement.className);
        NSArray<NSString *> *selectors = [@(requirement.selectors) componentsSeparatedByString:@"|"];
        NSArray<NSString *> *acceptedTypes = [@(requirement.types) componentsSeparatedByString:@"|"];
        NSMutableArray<NSString *> *sink = requirement.optional ? missingOptional : problems;

        Class cls = resolver(className);
        if (!cls) {
            if (![missingClasses containsObject:className]) {
                [missingClasses addObject:className];
                [problems addObject:[NSString stringWithFormat:@"class %@ not found", className]];
                [checks addObject:[NSString stringWithFormat:@"✗ class %@ missing", className]];
            }
            continue;
        }

        NSString *foundSelector = nil;
        NSString *foundTypes = nil;
        for (NSString *selectorName in selectors) {
            Method method = class_getInstanceMethod(cls, NSSelectorFromString(selectorName));
            if (!method) continue;
            const char *encoding = method_getTypeEncoding(method);
            foundSelector = selectorName;
            foundTypes = [self normalizedTypeEncoding:encoding ? @(encoding) : @""];
            if ([acceptedTypes containsObject:foundTypes]) break;
        }

        NSString *label = [NSString stringWithFormat:@"-[%@ %@]", className, foundSelector ?: [selectors componentsJoinedByString:@" | "]];
        if (!foundSelector) {
            [sink addObject:[NSString stringWithFormat:@"missing %@", label]];
            [checks addObject:[NSString stringWithFormat:@"%@ %@ missing", requirement.optional ? @"–" : @"✗", label]];
        } else if (![acceptedTypes containsObject:foundTypes]) {
            [sink addObject:[NSString stringWithFormat:@"incompatible %@: expected %@, found %@", label, [acceptedTypes componentsJoinedByString:@" or "], foundTypes]];
            [checks addObject:[NSString stringWithFormat:@"✗ %@ %@ (expected %@)", label, foundTypes, acceptedTypes.firstObject]];
        } else {
            [checks addObject:[NSString stringWithFormat:@"✓ %@ %@", label, foundTypes]];
        }
    }
    return [[T2MPrivateAPIReport alloc] initWithProblems:problems missingOptional:missingOptional checks:checks];
}

+ (NSString *)normalizedTypeEncoding:(NSString *)encoding {
    NSMutableString *result = [NSMutableString stringWithCapacity:encoding.length];
    for (NSUInteger i = 0; i < encoding.length; i++) {
        unichar c = [encoding characterAtIndex:i];
        if (c < '0' || c > '9') [result appendFormat:@"%C", c];
    }
    return result;
}

+ (NSArray<NSString *> *)runtimeInterfaceDump {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *name in @[kDescriptorClass, kModeClass, kSettingsClass, kDisplayClass]) {
        Class cls = NSClassFromString(name);
        if (!cls) {
            [lines addObject:[NSString stringWithFormat:@"%@: not present", name]];
            continue;
        }
        const char *image = class_getImageName(cls);
        [lines addObject:[NSString stringWithFormat:@"%@ (%s)", name, image ?: "?"]];
        unsigned int count = 0;
        objc_property_t *properties = class_copyPropertyList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            [lines addObject:[NSString stringWithFormat:@"  @property %s [%s]", property_getName(properties[i]), property_getAttributes(properties[i]) ?: ""]];
        }
        free(properties);
        Method *methods = class_copyMethodList(cls, &count);
        NSMutableArray<NSString *> *methodLines = [NSMutableArray array];
        for (unsigned int i = 0; i < count; i++) {
            const char *types = method_getTypeEncoding(methods[i]);
            [methodLines addObject:[NSString stringWithFormat:@"  -%@ %s", NSStringFromSelector(method_getName(methods[i])), types ?: ""]];
        }
        free(methods);
        [lines addObjectsFromArray:[methodLines sortedArrayUsingSelector:@selector(compare:)]];
    }
    return lines;
}

@end

#pragma mark - Value objects

@implementation T2MVirtualDisplayModeSpec

- (instancetype)initWithWidth:(uint32_t)width height:(uint32_t)height refreshRate:(double)refreshRate {
    if ((self = [super init])) {
        _width = width;
        _height = height;
        _refreshRate = refreshRate;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%u×%u@%.2fHz", _width, _height, _refreshRate];
}

@end

@implementation T2MVirtualDisplaySpec

- (instancetype)init {
    if ((self = [super init])) {
        _name = @"Virtual Display";
    }
    return self;
}

@end

#pragma mark - Display

@implementation T2MPrivateVirtualDisplay {
    id<T2MPrivateCGVirtualDisplay> _display;
    T2MClassResolver _resolver;
    dispatch_block_t _terminationHandler;
}

- (nullable instancetype)initWithSpec:(T2MVirtualDisplaySpec *)spec
                                modes:(NSArray<T2MVirtualDisplayModeSpec *> *)modes
                                hiDPI:(BOOL)hiDPI
                   terminationHandler:(dispatch_block_t)terminationHandler
                                error:(NSError **)error {
    return [self initWithSpec:spec
                        modes:modes
                        hiDPI:hiDPI
           terminationHandler:terminationHandler
                classResolver:^Class _Nullable(NSString *name) { return NSClassFromString(name); }
                        error:error];
}

- (nullable instancetype)initWithSpec:(T2MVirtualDisplaySpec *)spec
                                modes:(NSArray<T2MVirtualDisplayModeSpec *> *)modes
                                hiDPI:(BOOL)hiDPI
                   terminationHandler:(dispatch_block_t)terminationHandler
                        classResolver:(T2MClassResolver)classResolver
                                error:(NSError **)error {
    if (!(self = [super init])) return nil;

    T2MPrivateAPIReport *report = [T2MPrivateAPIChecker checkWithClassResolver:classResolver];
    if (!report.usable) {
        T2MSetError(error, T2MPrivateDisplayErrorUnavailable,
                    [NSString stringWithFormat:@"private CGVirtualDisplay API unavailable: %@", [report.problems componentsJoinedByString:@"; "]]);
        return nil;
    }
    _resolver = [classResolver copy];
    _terminationHandler = [terminationHandler copy];

    @try {
        Class descriptorClass = _resolver(kDescriptorClass);
        Class displayClass = _resolver(kDisplayClass);

        id<T2MPrivateCGVirtualDisplayDescriptor> descriptor = [(id<T2MPrivateCGVirtualDisplayDescriptor>)[descriptorClass alloc] init];
        if (!descriptor) {
            T2MSetError(error, T2MPrivateDisplayErrorCreationFailed, @"CGVirtualDisplayDescriptor -init returned nil");
            return nil;
        }
        [descriptor setName:spec.name];
        [descriptor setMaxPixelsWide:spec.maxPixelsWide];
        [descriptor setMaxPixelsHigh:spec.maxPixelsHigh];
        [descriptor setSizeInMillimeters:spec.sizeInMillimeters];
        [descriptor setVendorID:spec.vendorID];
        [descriptor setProductID:spec.productID];
        if ([descriptor respondsToSelector:@selector(setSerialNumber:)]) {
            [descriptor setSerialNumber:spec.serialNumber];
        } else {
            [descriptor setSerialNum:spec.serialNumber];
        }
        if ([descriptor respondsToSelector:@selector(setQueue:)]) {
            [descriptor setQueue:dispatch_get_main_queue()];
        } else {
            [descriptor setDispatchQueue:dispatch_get_main_queue()];
        }
        if (spec.hasColorPrimaries && [descriptor respondsToSelector:@selector(setRedPrimary:)] &&
            [descriptor respondsToSelector:@selector(setGreenPrimary:)] &&
            [descriptor respondsToSelector:@selector(setBluePrimary:)] &&
            [descriptor respondsToSelector:@selector(setWhitePoint:)]) {
            [descriptor setRedPrimary:spec.redPrimary];
            [descriptor setGreenPrimary:spec.greenPrimary];
            [descriptor setBluePrimary:spec.bluePrimary];
            [descriptor setWhitePoint:spec.whitePoint];
        }
        __weak T2MPrivateVirtualDisplay *weakSelf = self;
        [descriptor setTerminationHandler:^(id _Nullable __unused unused, id _Nullable __unused display) {
            [weakSelf handleTermination];
        }];

        id<T2MPrivateCGVirtualDisplay> display = [(id<T2MPrivateCGVirtualDisplay>)[displayClass alloc] initWithDescriptor:descriptor];
        unsigned int displayID = display ? [display displayID] : 0;
        if (displayID == 0) {
            T2MSetError(error, T2MPrivateDisplayErrorCreationFailed,
                        @"CGVirtualDisplay -initWithDescriptor: returned no display (vendorID must be non-zero and the identity unique)");
            return nil;
        }
        _display = display;
        _displayID = displayID;
    } @catch (NSException *exception) {
        _display = nil;
        T2MSetError(error, T2MPrivateDisplayErrorException, T2MDescribeException(exception));
        return nil;
    }

    if (![self applyModes:modes hiDPI:hiDPI error:error]) {
        [self invalidate];
        return nil;
    }
    return self;
}

- (BOOL)isValid {
    return _display != nil;
}

- (BOOL)applyModes:(NSArray<T2MVirtualDisplayModeSpec *> *)modes hiDPI:(BOOL)hiDPI error:(NSError **)error {
    if (!_display) {
        T2MSetError(error, T2MPrivateDisplayErrorInvalidated, @"the virtual display was already destroyed");
        return NO;
    }
    if (modes.count == 0) {
        T2MSetError(error, T2MPrivateDisplayErrorSettingsRejected, @"at least one mode is required");
        return NO;
    }
    @try {
        Class modeClass = _resolver(kModeClass);
        Class settingsClass = _resolver(kSettingsClass);
        NSMutableArray *privateModes = [NSMutableArray arrayWithCapacity:modes.count];
        for (T2MVirtualDisplayModeSpec *spec in modes) {
            id mode = [(id<T2MPrivateCGVirtualDisplayMode>)[modeClass alloc] initWithWidth:spec.width height:spec.height refreshRate:spec.refreshRate];
            if (!mode) {
                T2MSetError(error, T2MPrivateDisplayErrorSettingsRejected, [NSString stringWithFormat:@"mode %@ was rejected", spec]);
                return NO;
            }
            [privateModes addObject:mode];
        }
        id<T2MPrivateCGVirtualDisplaySettings> settings = [(id<T2MPrivateCGVirtualDisplaySettings>)[settingsClass alloc] init];
        [settings setHiDPI:hiDPI ? 1 : 0];
        [settings setModes:privateModes];
        if (![_display applySettings:settings]) {
            T2MSetError(error, T2MPrivateDisplayErrorSettingsRejected,
                        [NSString stringWithFormat:@"-applySettings: returned NO for %lu mode(s), hiDPI=%d", (unsigned long)modes.count, hiDPI]);
            return NO;
        }
        return YES;
    } @catch (NSException *exception) {
        T2MSetError(error, T2MPrivateDisplayErrorException, T2MDescribeException(exception));
        return NO;
    }
}

- (void)invalidate {
    @try {
        _display = nil;  // CGVirtualDisplay removes the display when deallocated
    } @catch (NSException *exception) {
        NSLog(@"[Tab2Mac] exception while releasing virtual display %u: %@", _displayID, T2MDescribeException(exception));
    }
    _terminationHandler = nil;
}

- (void)handleTermination {
    dispatch_block_t handler = _terminationHandler;
    if (handler) handler();
}

@end
