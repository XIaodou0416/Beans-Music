// WCLGEdgeEffect.m

#import "WCLGEdgeEffect.h"
#import "WCLGBackdropLayer.h"
#import "WCLGEdgeGradientTables.h"
#import <math.h>
#import <objc/runtime.h>
#import <objc/message.h>

// 贴 telegram-ios EdgeEffect 的 maxBlurRadius(=1.0)，仅做轻微柔化；内容消失主要靠同色色板。
static const CGFloat kWCLGEdgeVariableBlurRadius = 1.0;
// 模糊是低频信息，半分辨率采样肉眼几乎无差，GPU 开销减半以上（性能优化 Tier2）。
static const CGFloat kWCLGEdgeBackdropScale = 0.5;

@interface WCLGVariableBlurHostView : UIView
@property (nonatomic, strong, nullable) CALayer *backdropLayer;
@property (nonatomic, strong, nullable) UIImage *gradientImage;
@property (nonatomic, strong, nullable) id variableBlurFilter;
@property (nonatomic, assign) CGSize lastSize;
@property (nonatomic, assign) CGFloat lastConstantHeight;
@property (nonatomic, assign) BOOL lastInverted;
@property (nonatomic, assign) CGFloat lastGradientHeight;
@property (nonatomic, assign) CGFloat lastBlurRadius;
@end

@implementation WCLGVariableBlurHostView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.opaque = NO;
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = NO;
        self.layer.name = @"WCLGVariableBlurHost";

        _backdropLayer = WCLGBackdropLayerCreate();
        if (_backdropLayer) {
            _backdropLayer.frame = self.bounds;
            _backdropLayer.masksToBounds = YES;
            WCLGBackdropLayerSetScale(_backdropLayer, kWCLGEdgeBackdropScale);
            [self.layer addSublayer:_backdropLayer];
        }
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.backdropLayer.frame = self.bounds;
}

@end

static id WCLGEdgeMakeVariableBlurFilter(void) {
    Class filterClass = NSClassFromString(@"CAFilter");
    if (!filterClass) return nil;
    SEL selector = NSSelectorFromString(@"filterWithName:");
    if (![filterClass respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL, NSString *))objc_msgSend)(filterClass, selector, @"variableBlur");
}

BOOL WCLGEdgeVariableBlurIsAvailable(void) {
    static dispatch_once_t onceToken;
    static BOOL available = NO;
    dispatch_once(&onceToken, ^{
        available = WCLGEdgeMakeVariableBlurFilter() != nil && WCLGBackdropLayerCreate() != nil;
    });
    return available;
}

static UIImage *WCLGEdgeGenerateGradientImage(CGSize size, BOOL inverted) {
    if (size.width <= 0.0 || size.height <= 0.0) return nil;

    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) {
        UIGraphicsEndImageContext();
        return nil;
    }

    CGContextClearRect(context, CGRectMake(0.0, 0.0, size.width, size.height));

    NSMutableArray *cgColors = [NSMutableArray arrayWithCapacity:kWCLGEdgeGradientStopCount];
    for (size_t i = 0; i < kWCLGEdgeGradientStopCount; i++) {
        CGFloat alpha = kWCLGEdgeGradientAlphas[i] / kWCLGEdgeGradientAlphaNorm;
        UIColor *color = [UIColor colorWithWhite:0.0 alpha:alpha];
        [cgColors addObject:(id)color.CGColor];
    }

    CGFloat locations[kWCLGEdgeGradientStopCount];
    memcpy(locations, kWCLGEdgeGradientLocations, sizeof(locations));

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColors(colorSpace,
                                                        (__bridge CFArrayRef)cgColors,
                                                        locations);
    if (gradient) {
        CGPoint start = inverted ? CGPointMake(0.0, size.height) : CGPointMake(0.0, 0.0);
        CGPoint end = inverted ? CGPointMake(0.0, 0.0) : CGPointMake(0.0, size.height);
        CGContextDrawLinearGradient(context, gradient, start, end, 0);
        CGGradientRelease(gradient);
    }
    CGColorSpaceRelease(colorSpace);

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

UIImage *WCLGEdgeGradientMaskImage(CGFloat baseHeight, BOOL inverted) {
    CGFloat scale = MAX(UIScreen.mainScreen.scale, 1.0);
    CGFloat height = MAX(1.0, round(baseHeight * scale) / scale);
    static NSCache<NSString *, UIImage *> *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 96;
    });
    NSString *key = [NSString stringWithFormat:@"%.0f:%ld:%d",
                     height * scale,
                     (long)llround(scale),
                     inverted];
    UIImage *cached = [cache objectForKey:key];
    if (cached) return cached;

    UIImage *image = WCLGEdgeGenerateGradientImage(CGSizeMake(1.0, height), inverted);
    if (!image) return nil;
    UIEdgeInsets caps = inverted ? UIEdgeInsetsMake(0.0, 0.0, height, 0.0)
                                 : UIEdgeInsetsMake(height, 0.0, 0.0, 0.0);
    UIImage *resizable = [image resizableImageWithCapInsets:caps resizingMode:UIImageResizingModeStretch];
    if (resizable) [cache setObject:resizable forKey:key];
    return resizable;
}

static UIImage *WCLGEdgeLegacyMaskComposite(CGSize size,
                                            CGFloat constantHeight,
                                            BOOL inverted,
                                            UIImage *gradientImage) {
    if (!gradientImage || size.width <= 0.0 || size.height <= 0.0) return nil;

    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) {
        UIGraphicsEndImageContext();
        return nil;
    }

    CGRect bounds = CGRectMake(0.0, 0.0, size.width, size.height);
    CGContextClearRect(context, bounds);

    CGRect mainFrame;
    CGRect additionalFrame;
    if (inverted) {
        mainFrame = CGRectMake(0.0, 0.0, size.width, constantHeight);
        additionalFrame = CGRectMake(0.0, constantHeight, size.width, MAX(0.0, size.height - constantHeight));
    } else {
        mainFrame = CGRectMake(0.0, size.height - constantHeight, size.width, constantHeight);
        additionalFrame = CGRectMake(0.0, 0.0, size.width, MAX(0.0, size.height - constantHeight));
    }

    CGContextSetFillColorWithColor(context, UIColor.blackColor.CGColor);
    CGContextFillRect(context, additionalFrame);
    [gradientImage drawInRect:mainFrame blendMode:kCGBlendModeNormal alpha:1.0];

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

static void WCLGEdgeApplyVariableBlur(WCLGVariableBlurHostView *host,
                                      CGSize size,
                                      CGFloat constantHeight,
                                      BOOL inverted,
                                      CGFloat gradientHeight,
                                      CGFloat blurRadius) {
    if (!host.backdropLayer) return;

    BOOL sizeChanged = !CGSizeEqualToSize(host.lastSize, size);
    BOOL heightChanged = fabs(host.lastConstantHeight - constantHeight) > 0.5 ||
                         fabs(host.lastGradientHeight - gradientHeight) > 0.5 ||
                         host.lastInverted != inverted;
    CGFloat resolvedRadius = blurRadius > 0.01 ? blurRadius : kWCLGEdgeVariableBlurRadius;
    BOOL radiusChanged = fabs(host.lastBlurRadius - resolvedRadius) > 0.05;
    NSArray *filters = [host.backdropLayer valueForKey:@"filters"];
    BOOL filterAttached = host.variableBlurFilter &&
                          [filters containsObject:host.variableBlurFilter];
    if (!sizeChanged && !heightChanged && !radiusChanged && host.gradientImage && filterAttached) {
        host.backdropLayer.frame = CGRectMake(0.0, 0.0, size.width, size.height);
        return;
    }

    UIImage *stretchMask = WCLGEdgeGradientMaskImage(MAX(1.0, gradientHeight), inverted);
    UIImage *maskComposite = WCLGEdgeLegacyMaskComposite(size, constantHeight, inverted, stretchMask);
    host.gradientImage = stretchMask;
    host.lastSize = size;
    host.lastConstantHeight = constantHeight;
    host.lastInverted = inverted;
    host.lastGradientHeight = gradientHeight;
    host.lastBlurRadius = resolvedRadius;

    id variableBlur = host.variableBlurFilter;
    if (!variableBlur) {
        variableBlur = WCLGEdgeMakeVariableBlurFilter();
        host.variableBlurFilter = variableBlur;
    }
    if (!variableBlur || !maskComposite.CGImage) {
        [host.backdropLayer setValue:nil forKey:@"filters"];
        return;
    }

    [variableBlur setValue:@(resolvedRadius) forKey:@"inputRadius"];
    [variableBlur setValue:(__bridge id)maskComposite.CGImage forKey:@"inputMaskImage"];
    [variableBlur setValue:@YES forKey:@"inputNormalizeEdges"];
    [host.backdropLayer setValue:@[ variableBlur ] forKey:@"filters"];
    host.backdropLayer.frame = CGRectMake(0.0, 0.0, size.width, size.height);
}

@interface WCLGEdgeEffectView ()
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIImageView *contentMaskView;
@property (nonatomic, strong) WCLGVariableBlurHostView *blurHostView;
@property (nonatomic, strong, nullable) UIVisualEffectView *fallbackBlurView;
@property (nonatomic, strong, nullable) UIColor *lastContentColor;
@property (nonatomic, assign) BOOL lastBlur;
@property (nonatomic, assign) CGFloat lastAlpha;
@property (nonatomic, assign) CGRect lastRect;
@property (nonatomic, assign) WCLGEdgeEffectEdge lastEdge;
@property (nonatomic, assign) CGFloat lastEdgeSize;
@property (nonatomic, assign) CGFloat lastEdgeInset;
@property (nonatomic, assign) CGFloat lastTransitionLength;
@property (nonatomic, assign) CGFloat lastBlurRadius;
@end

@implementation WCLGEdgeEffectView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.opaque = NO;
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = NO;
        self.layer.name = NSStringFromClass(self.class);
        _blurEnabled = YES;

        _blurHostView = [[WCLGVariableBlurHostView alloc] initWithFrame:CGRectZero];
        [self addSubview:_blurHostView];

        _contentView = [[UIView alloc] initWithFrame:CGRectZero];
        _contentMaskView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _contentView.maskView = _contentMaskView;
        [self addSubview:_contentView];
    }
    return self;
}

- (void)updateWithContentColor:(UIColor *)contentColor
                          blur:(BOOL)blur
                         alpha:(CGFloat)alpha
                          rect:(CGRect)rect
                          edge:(WCLGEdgeEffectEdge)edge
                      edgeSize:(CGFloat)edgeSize
                    blurRadius:(CGFloat)blurRadius {
    [self updateWithContentColor:contentColor
                            blur:blur
                           alpha:alpha
                            rect:rect
                            edge:edge
                       edgeInset:0.0
                transitionLength:edgeSize
                      blurRadius:blurRadius];
}

- (void)updateWithContentColor:(UIColor *)contentColor
                          blur:(BOOL)blur
                         alpha:(CGFloat)alpha
                          rect:(CGRect)rect
                          edge:(WCLGEdgeEffectEdge)edge
                     edgeInset:(CGFloat)edgeInset
              transitionLength:(CGFloat)transitionLength
                    blurRadius:(CGFloat)blurRadius {
    UIColor *resolvedColor = contentColor ?: UIColor.whiteColor;
    CGFloat clampedAlpha = MIN(1.0, MAX(0.0, alpha));
    CGFloat clampedInset = MAX(0.0, edgeInset);
    CGFloat clampedTransition = MAX(1.0, transitionLength);
    CGFloat availableHeight = MAX(1.0, CGRectGetHeight(rect));
    if (clampedInset + clampedTransition > availableHeight) {
        clampedInset = MAX(0.0, availableHeight - clampedTransition);
        clampedTransition = MIN(clampedTransition, availableHeight);
    }
    CGFloat clampedEdgeSize = MIN(availableHeight, clampedInset + clampedTransition);
    CGFloat clampedBlurRadius = MAX(0.0, blurRadius);
    BOOL inverted = edge == WCLGEdgeEffectEdgeBottom;
    // 模糊度为 0 时彻底不挂模糊滤镜，壁纸保持清晰，仅留同色色板渐隐。
    BOOL wantsAnyBlur = blur && self.blurEnabled && clampedBlurRadius > 0.01;
    BOOL wantsBlur = wantsAnyBlur && WCLGEdgeVariableBlurIsAvailable();
    if (self.lastContentColor &&
        [self.lastContentColor isEqual:resolvedColor] &&
        self.lastBlur == wantsBlur &&
        fabs(self.lastAlpha - clampedAlpha) < 0.001 &&
        CGRectEqualToRect(self.lastRect, rect) &&
        self.lastEdge == edge &&
        fabs(self.lastEdgeSize - clampedEdgeSize) < 0.5 &&
        fabs(self.lastEdgeInset - clampedInset) < 0.5 &&
        fabs(self.lastTransitionLength - clampedTransition) < 0.5 &&
        fabs(self.lastBlurRadius - clampedBlurRadius) < 0.05) {
        return;
    }

    self.lastContentColor = resolvedColor;
    self.lastBlur = wantsBlur;
    self.lastAlpha = clampedAlpha;
    self.lastRect = rect;
    self.lastEdge = edge;
    self.lastEdgeSize = clampedEdgeSize;
    self.lastEdgeInset = clampedInset;
    self.lastTransitionLength = clampedTransition;
    self.lastBlurRadius = clampedBlurRadius;

    CGRect bounds = CGRectMake(0.0, 0.0, rect.size.width, rect.size.height);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    self.contentView.frame = bounds;
    self.contentMaskView.frame = bounds;
    self.contentView.backgroundColor = resolvedColor;
    self.contentView.alpha = clampedAlpha;

    UIImage *gradientImage = WCLGEdgeGradientMaskImage(clampedTransition, inverted);
    UIImage *maskImage = WCLGEdgeLegacyMaskComposite(bounds.size,
                                                      clampedTransition,
                                                      inverted,
                                                      gradientImage);
    self.contentMaskView.image = maskImage;

    if (wantsBlur) {
        self.fallbackBlurView.hidden = YES;
        self.blurHostView.hidden = NO;

        CGRect blurFrame = bounds;
        self.blurHostView.frame = blurFrame;
        WCLGEdgeApplyVariableBlur(self.blurHostView,
                                    blurFrame.size,
                                    clampedTransition,
                                    inverted,
                                    clampedTransition,
                                    clampedBlurRadius);
    } else if (wantsAnyBlur) {
        self.blurHostView.hidden = YES;
        [self.blurHostView.backdropLayer setValue:nil forKey:@"filters"];
        UIVisualEffectView *fallback = self.fallbackBlurView;
        if (!fallback) {
            fallback = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleLight]];
            fallback.userInteractionEnabled = NO;
            self.fallbackBlurView = fallback;
            [self insertSubview:fallback belowSubview:self.contentView];
        }
        fallback.hidden = NO;
        fallback.frame = bounds;
        fallback.alpha = clampedAlpha;
        if (maskImage) {
            UIImageView *blurMask = (UIImageView *)fallback.maskView;
            if (![blurMask isKindOfClass:[UIImageView class]]) {
                blurMask = [[UIImageView alloc] initWithFrame:fallback.bounds];
                fallback.maskView = blurMask;
            }
            blurMask.frame = fallback.bounds;
            blurMask.image = maskImage;
        }
    } else {
        self.blurHostView.hidden = YES;
        [self.blurHostView.backdropLayer setValue:nil forKey:@"filters"];
        self.fallbackBlurView.hidden = YES;
    }

    [CATransaction commit];
}

@end
