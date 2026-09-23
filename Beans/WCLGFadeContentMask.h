#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 给滚动内容增加顶部/底部透明渐隐；inset 是贴边透明区，band 是过渡长度。
void WCLGFadeContentMaskApply(UIScrollView *scrollView,
                              CGFloat topInset,
                              CGFloat topBand,
                              CGFloat bottomInset,
                              CGFloat bottomBand);

/// 滚动或 bounds 改变时调用，只做 O(1) 的 mask frame 校正。
void WCLGFadeContentMaskUpdateFrame(UIScrollView *scrollView);

/// 仅移除本模块创建的 mask；发现外部 mask 时不抢占。
void WCLGFadeContentMaskRemove(UIScrollView *scrollView);

NS_ASSUME_NONNULL_END
