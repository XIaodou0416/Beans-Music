// WCLGBackdropLayer.m

#import "WCLGBackdropLayer.h"
#import <objc/runtime.h>
#import <objc/message.h>

static Class WCLGBackdropLayerClass(void) {
    static Class cls = Nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cls = NSClassFromString(@"CABackdropLayer");
    });
    return cls;
}

CALayer *WCLGBackdropLayerCreate(void) {
    Class cls = WCLGBackdropLayerClass();
    if (!cls) return nil;
    id instance = ((id (*)(id, SEL))objc_msgSend)(cls, @selector(alloc));
    if (!instance) return nil;
    id layer = ((id (*)(id, SEL))objc_msgSend)(instance, @selector(init));
    if (![layer isKindOfClass:[CALayer class]]) return nil;
    return (CALayer *)layer;
}

void WCLGBackdropLayerSetScale(CALayer *layer, CGFloat scale) {
    if (!layer) return;
    if ([layer respondsToSelector:@selector(setScale:)]) {
        ((void (*)(id, SEL, double))objc_msgSend)(layer, @selector(setScale:), (double)scale);
    } else {
        [layer setValue:@(scale) forKey:@"scale"];
    }
}
