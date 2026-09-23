#import "WCLGFadeContentMask.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static char kWCLGFadeMaskLayerKey;
static char kWCLGFadeMaskSignatureKey;

static NSArray<NSNumber *> *WCLGFadeMaskSignature(CGRect bounds,
                                                   CGFloat topInset,
                                                   CGFloat topBand,
                                                   CGFloat bottomInset,
                                                   CGFloat bottomBand) {
    return @[@(CGRectGetWidth(bounds)), @(CGRectGetHeight(bounds)),
             @(topInset), @(topBand), @(bottomInset), @(bottomBand)];
}

void WCLGFadeContentMaskRemove(UIScrollView *scrollView) {
    if (!scrollView) return;
    CALayer *mask = objc_getAssociatedObject(scrollView, &kWCLGFadeMaskLayerKey);
    if (mask && scrollView.layer.mask == mask) scrollView.layer.mask = nil;
    objc_setAssociatedObject(scrollView, &kWCLGFadeMaskLayerKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(scrollView, &kWCLGFadeMaskSignatureKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void WCLGFadeContentMaskUpdateFrame(UIScrollView *scrollView) {
    if (!scrollView) return;
    CAGradientLayer *mask = objc_getAssociatedObject(scrollView, &kWCLGFadeMaskLayerKey);
    if (![mask isKindOfClass:CAGradientLayer.class] || scrollView.layer.mask != mask) return;
    CGRect bounds = scrollView.bounds;
    if (CGRectGetWidth(bounds) < 1.0 || CGRectGetHeight(bounds) < 1.0 ||
        CGRectEqualToRect(mask.frame, bounds)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    mask.frame = bounds;
    [CATransaction commit];
}

void WCLGFadeContentMaskApply(UIScrollView *scrollView,
                              CGFloat topInset,
                              CGFloat topBand,
                              CGFloat bottomInset,
                              CGFloat bottomBand) {
    if (!scrollView) return;
    CGRect bounds = scrollView.bounds;
    CGFloat height = CGRectGetHeight(bounds);
    if (CGRectGetWidth(bounds) < 1.0 || height < 1.0) return;

    CAGradientLayer *mask = objc_getAssociatedObject(scrollView, &kWCLGFadeMaskLayerKey);
    CALayer *currentMask = scrollView.layer.mask;
    if (currentMask && currentMask != mask) return;

    BOOL wantsTop = topBand > 0.0;
    BOOL wantsBottom = bottomBand > 0.0;
    if (!wantsTop && !wantsBottom) {
        WCLGFadeContentMaskRemove(scrollView);
        return;
    }

    topInset = wantsTop ? MAX(0.0, topInset) : 0.0;
    bottomInset = wantsBottom ? MAX(0.0, bottomInset) : 0.0;
    topBand = wantsTop ? MAX(1.0, topBand) : 0.0;
    bottomBand = wantsBottom ? MAX(1.0, bottomBand) : 0.0;

    // 顶底总渐隐区最多占可视高度 85%，避免参数错误导致整屏透明。
    CGFloat used = topInset + topBand + bottomInset + bottomBand;
    CGFloat maxUsed = height * 0.85;
    if (used > maxUsed && used > 1.0) {
        CGFloat scale = maxUsed / used;
        topInset *= scale;
        topBand *= scale;
        bottomInset *= scale;
        bottomBand *= scale;
    }

    NSArray<NSNumber *> *signature = WCLGFadeMaskSignature(
        bounds, topInset, topBand, bottomInset, bottomBand);
    NSArray<NSNumber *> *lastSignature =
        objc_getAssociatedObject(scrollView, &kWCLGFadeMaskSignatureKey);
    if (mask && scrollView.layer.mask == mask && [lastSignature isEqual:signature]) {
        WCLGFadeContentMaskUpdateFrame(scrollView);
        return;
    }

    CGFloat topStart = topInset / height;
    CGFloat topEnd = (topInset + topBand) / height;
    CGFloat bottomStart = (height - bottomInset - bottomBand) / height;
    CGFloat bottomEnd = (height - bottomInset) / height;
    topStart = MIN(MAX(topStart, 0.0), 1.0);
    topEnd = MIN(MAX(topEnd, topStart), 1.0);
    bottomStart = MIN(MAX(bottomStart, topEnd), 1.0);
    bottomEnd = MIN(MAX(bottomEnd, bottomStart), 1.0);

    if (!mask) {
        mask = [CAGradientLayer layer];
        mask.name = @"WCLGFadeContentMask";
        mask.anchorPoint = CGPointZero;
        mask.startPoint = CGPointMake(0.5, 0.0);
        mask.endPoint = CGPointMake(0.5, 1.0);
        objc_setAssociatedObject(scrollView, &kWCLGFadeMaskLayerKey, mask,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    id clear = (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor;
    id solid = (__bridge id)[UIColor colorWithWhite:1.0 alpha:1.0].CGColor;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    mask.colors = @[wantsTop ? clear : solid, solid, solid,
                    wantsBottom ? clear : solid];
    mask.locations = @[@(topStart), @(topEnd), @(bottomStart), @(bottomEnd)];
    mask.frame = bounds;
    scrollView.layer.mask = mask;
    [CATransaction commit];

    objc_setAssociatedObject(scrollView, &kWCLGFadeMaskSignatureKey, signature,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
}
