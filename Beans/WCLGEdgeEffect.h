// WCLGEdgeEffect.h
// Telegram-style edge fade: variable blur + tinted scrim mask.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WCLGEdgeEffectEdge) {
    WCLGEdgeEffectEdgeTop = 0,
    WCLGEdgeEffectEdgeBottom = 1,
};

@interface WCLGEdgeEffectView : UIView

@property (nonatomic, assign, getter=isBlurEnabled) BOOL blurEnabled;

- (void)updateWithContentColor:(UIColor *)contentColor
                          blur:(BOOL)blur
                         alpha:(CGFloat)alpha
                          rect:(CGRect)rect
                          edge:(WCLGEdgeEffectEdge)edge
                      edgeSize:(CGFloat)edgeSize
                    blurRadius:(CGFloat)blurRadius;

- (void)updateWithContentColor:(UIColor *)contentColor
                          blur:(BOOL)blur
                         alpha:(CGFloat)alpha
                          rect:(CGRect)rect
                          edge:(WCLGEdgeEffectEdge)edge
                     edgeInset:(CGFloat)edgeInset
              transitionLength:(CGFloat)transitionLength
                    blurRadius:(CGFloat)blurRadius;

@end

UIImage *_Nullable WCLGEdgeGradientMaskImage(CGFloat baseHeight, BOOL inverted);
BOOL WCLGEdgeVariableBlurIsAvailable(void);

NS_ASSUME_NONNULL_END
