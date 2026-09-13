(function(){
  var style = document.createElement('style');
  style.textContent = `
    html.ios-shell-root, html.ios-shell-root body {
      width: 100vw !important;
      min-width: 0 !important;
      height: 100vh !important;
      overflow: hidden !important;
      background: #000 !important;
      touch-action: manipulation;
      -webkit-user-select: none;
      user-select: none;
    }
    html.ios-shell-root body.desktop-shell #desktop-window-shell {
      border-radius: 0 !important;
      clip-path: none !important;
      box-shadow: none !important;
    }
    html.ios-shell-root #desktop-titlebar,
    html.ios-shell-root #fullscreen-diy-zone,
    html.ios-shell-root #update-entry,
    html.ios-shell-root #trial-banner,
    html.ios-shell-root #ai-depth-chip,
    html.ios-shell-root #beat-chip,
    html.ios-shell-root #bottom-handle,
    html.ios-shell-root #user-capsule-hide-btn,
    html.ios-shell-root #upload-actions,
    html.ios-shell-root #upload-tip {
      display: none !important;
    }
    html.ios-shell-root body.user-capsule-auto-hide #top-right,
    html.ios-shell-root body.user-capsule-auto-hide.user-capsule-peek #top-right {
      right: 56px !important;
      opacity: 1 !important;
      visibility: visible !important;
      pointer-events: auto !important;
    }
    html.ios-shell-root #search-area,
    html.ios-shell-root body.simple-mode #search-area {
      left: 50% !important;
      width: calc(100vw - 28px) !important;
      max-width: 520px !important;
      transform: translateX(-50%) !important;
      z-index: 540 !important;
      align-items: stretch !important;
    }
    html.ios-shell-root #search-area.peek,
    html.ios-shell-root body.simple-mode #search-area.peek,
    html.ios-shell-root body.desktop-shell.simple-mode #search-area.peek {
      top: max(88px, env(safe-area-inset-top) + 62px) !important;
    }
    html.ios-shell-root #search-box {
      min-width: 0 !important;
      height: 48px !important;
      border-radius: 18px !important;
    }
    html.ios-shell-root #search-input {
      min-width: 0 !important;
      font-size: 13px !important;
    }
    html.ios-shell-root #search-mode-tabs {
      transform: scale(.92) !important;
      transform-origin: left top !important;
    }
    html.ios-shell-root #search-stack,
    html.ios-shell-root body.simple-mode #search-stack {
      width: 100% !important;
    }
    html.ios-shell-root #playlist-panel {
      top: max(72px, env(safe-area-inset-top) + 54px) !important;
      left: -86vw !important;
      width: min(82vw, 340px) !important;
      max-height: calc(100vh - 168px) !important;
    }
    html.ios-shell-root #playlist-panel.peek,
    html.ios-shell-root #playlist-panel.pinned {
      left: 10px !important;
    }
    html.ios-shell-root #bottom-bar {
      left: 12px !important;
      right: 12px !important;
      bottom: max(12px, env(safe-area-inset-bottom)) !important;
      width: auto !important;
      max-width: none !important;
      transform: none !important;
      border-radius: 26px !important;
      z-index: 530 !important;
    }
    html.ios-shell-root #bottom-bar:not(.visible) {
      opacity: 1 !important;
      transform: translateY(0) !important;
      pointer-events: auto !important;
    }
    html.ios-shell-root body.splash-active #bottom-bar,
    html.ios-shell-root body.splash-active #bottom-handle,
    html.ios-shell-root body.splash-active #ios-tabbar {
      opacity: 0 !important;
      transform: translateY(22px) !important;
      pointer-events: none !important;
    }
    html.ios-shell-root #hint {
      display: block !important;
      opacity: .72 !important;
    }
    html.ios-shell-root #login-modal.show {
      display: flex !important;
      opacity: 1 !important;
      pointer-events: auto !important;
      z-index: 2000 !important;
    }
    html.ios-shell-root #login-modal .modal.dual-login-modal {
      width: min(470px, 92vw) !important;
      max-height: 86vh !important;
      overflow-y: auto !important;
    }
    html.ios-shell-root #canvas-container {
      opacity: 1 !important;
      transform: none !important;
    }
    html.ios-shell-root #photo-deck {
      width: calc(100vw - 24px) !important;
      min-width: 0 !important;
      bottom: max(92px, env(safe-area-inset-bottom) + 82px) !important;
    }
    html.ios-shell-root .photo-deck-title { max-width: 46vw !important; }
    html.ios-shell-root #top-right {
      top: max(52px, env(safe-area-inset-top) + 22px) !important;
      right: 12px !important;
      transform: scale(.82) !important;
      transform-origin: top right !important;
      z-index: 545 !important;
    }
    html.ios-shell-root #top-right .top-account-name,
    html.ios-shell-root #top-right .top-account-vip {
      display: none !important;
    }
    html.ios-shell-root #top-right .top-account-pill {
      width: 36px !important;
      height: 36px !important;
      min-width: 36px !important;
      padding: 0 !important;
      justify-content: center !important;
    }
    html.ios-shell-root #top-right .top-account-pill img {
      width: 30px !important;
      height: 30px !important;
    }
    html.ios-shell-root #empty-home {
      top: max(142px, env(safe-area-inset-top) + 116px) !important;
      bottom: max(146px, env(safe-area-inset-bottom) + 132px) !important;
      width: calc(100vw - 24px) !important;
      overflow: hidden !important;
    }
    html.ios-shell-root body.ios-player-expanded #empty-home {
      bottom: max(212px, env(safe-area-inset-bottom) + 198px) !important;
    }
    html.ios-shell-root .empty-home-shell {
      min-height: 0 !important;
      height: 100% !important;
      grid-template-columns: 1fr !important;
      grid-template-rows: auto 1fr !important;
      gap: 10px !important;
      overflow-y: auto !important;
      overscroll-behavior: contain !important;
      padding-bottom: 6px !important;
      scrollbar-width: none !important;
    }
    html.ios-shell-root .empty-home-shell::-webkit-scrollbar { display: none !important; }
    html.ios-shell-root .home-hero {
      min-height: 208px !important;
      padding: 18px !important;
      border-radius: 24px !important;
      grid-row: auto !important;
    }
    html.ios-shell-root .home-hero-inner {
      display: flex !important;
      flex-direction: column !important;
      align-items: flex-start !important;
      justify-content: space-between !important;
      gap: 12px !important;
    }
    html.ios-shell-root .home-kicker {
      margin-bottom: 0 !important;
      font-size: 9px !important;
    }
    html.ios-shell-root .home-title,
    html.ios-shell-root .home-title.home-construction-title {
      max-width: 260px !important;
      font-size: 31px !important;
      line-height: 1.02 !important;
    }
    html.ios-shell-root .home-sub {
      max-width: 280px !important;
      font-size: 12px !important;
      line-height: 1.45 !important;
      margin-top: 0 !important;
    }
    html.ios-shell-root .home-visual,
    html.ios-shell-root .home-mosaic,
    html.ios-shell-root .home-section-head {
      display: none !important;
    }
    html.ios-shell-root .home-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr)) !important;
      gap: 8px !important;
    }
    html.ios-shell-root .home-rail,
    html.ios-shell-root .home-tile-row {
      display: none !important;
    }
    html.ios-shell-root .home-card {
      min-height: 96px !important;
      padding: 11px !important;
      border-radius: 17px !important;
    }
    html.ios-shell-root .home-card-label {
      font-size: 8.5px !important;
      margin-bottom: 6px !important;
    }
    html.ios-shell-root .home-card-title {
      font-size: 15px !important;
      max-width: 74% !important;
    }
    html.ios-shell-root .home-card-sub {
      font-size: 10px !important;
      line-height: 1.25 !important;
      max-width: 70% !important;
      display: -webkit-box !important;
      -webkit-line-clamp: 2 !important;
      -webkit-box-orient: vertical !important;
      overflow: hidden !important;
    }
    html.ios-shell-root .home-card-art {
      width: 52px !important;
      height: 52px !important;
      right: 9px !important;
      bottom: 9px !important;
      border-radius: 14px !important;
    }
    html.ios-shell-root #bottom-bar {
      box-sizing: border-box !important;
      min-height: 96px !important;
      max-height: 110px !important;
      padding: 9px 12px 13px !important;
      gap: 5px !important;
      overflow: visible !important;
    }
    html.ios-shell-root body.ios-player-expanded #bottom-bar {
      min-height: 146px !important;
      max-height: 158px !important;
      padding: 9px 12px 14px !important;
    }
    html.ios-shell-root #progress-bar {
      width: calc(100% - 24px) !important;
      height: 3px !important;
      margin: 0 auto 1px !important;
    }
    html.ios-shell-root #controls {
      display: grid !important;
      grid-template-columns: minmax(0, 1fr) auto !important;
      grid-template-rows: 52px !important;
      align-items: center !important;
      gap: 3px !important;
      width: 100% !important;
    }
    html.ios-shell-root body.ios-player-expanded #controls {
      grid-template-columns: 1fr !important;
      grid-template-rows: 38px 52px 36px !important;
    }
    html.ios-shell-root .control-cluster {
      grid-column: 1 !important;
      width: 100% !important;
      min-width: 0 !important;
      height: auto !important;
    }
    html.ios-shell-root .control-cluster.actions {
      grid-row: 1 !important;
      grid-column: 1 !important;
      order: 1 !important;
      display: flex !important;
      justify-content: flex-start !important;
      gap: 8px !important;
      overflow: hidden !important;
    }
    html.ios-shell-root .control-cluster.transport {
      grid-row: 1 !important;
      grid-column: 2 !important;
      order: 2 !important;
      justify-content: center !important;
      gap: 6px !important;
    }
    html.ios-shell-root body.ios-player-expanded .control-cluster.transport {
      grid-row: 2 !important;
      grid-column: 1 !important;
      gap: 9px !important;
    }
    html.ios-shell-root .control-cluster.modes {
      display: none !important;
    }
    html.ios-shell-root body.ios-player-expanded .control-cluster.modes {
      display: flex !important;
      grid-row: 3 !important;
      order: 3 !important;
      justify-content: flex-start !important;
      gap: 8px !important;
      overflow-x: auto !important;
      overflow-y: hidden !important;
      padding: 0 2px 1px !important;
      scrollbar-width: none !important;
      -webkit-overflow-scrolling: touch !important;
    }
    html.ios-shell-root body.ios-player-expanded .control-cluster.modes::-webkit-scrollbar {
      display: none !important;
    }
    html.ios-shell-root .control-track {
      display: flex !important;
      flex: 1 1 auto !important;
      min-width: 0 !important;
      gap: 8px !important;
    }
    html.ios-shell-root .control-cover {
      display: block !important;
      width: 34px !important;
      height: 34px !important;
      border-radius: 10px !important;
    }
    html.ios-shell-root .control-meta {
      flex: 1 1 auto !important;
      max-width: none !important;
      min-width: 0 !important;
      gap: 2px !important;
    }
    html.ios-shell-root .control-title { font-size: 11px !important; }
    html.ios-shell-root .control-artist { font-size: 10px !important; }
    html.ios-shell-root .ctrl-btn {
      width: 40px !important;
      height: 40px !important;
      border-radius: 13px !important;
    }
    html.ios-shell-root .ctrl-btn svg {
      width: 18px !important;
      height: 18px !important;
    }
    html.ios-shell-root #quality-control,
    html.ios-shell-root #play-mode-btn,
    html.ios-shell-root #mini-queue-btn {
      display: none !important;
    }
    html.ios-shell-root body.ios-player-expanded #quality-control,
    html.ios-shell-root body.ios-player-expanded #play-mode-btn,
    html.ios-shell-root body.ios-player-expanded #mini-queue-btn,
    html.ios-shell-root #heart-btn,
    html.ios-shell-root #collect-btn {
      flex: 0 0 auto !important;
    }
    html.ios-shell-root body.ios-player-expanded #quality-control,
    html.ios-shell-root body.ios-player-expanded #play-mode-btn,
    html.ios-shell-root body.ios-player-expanded #mini-queue-btn {
      display: flex !important;
    }
    html.ios-shell-root #quality-btn.quality-pill {
      min-width: 44px !important;
      height: 34px !important;
      padding: 0 8px !important;
      font-size: 10px !important;
    }
    html.ios-shell-root #play-btn {
      width: 52px !important;
      height: 52px !important;
    }
    html.ios-shell-root #prev-btn,
    html.ios-shell-root #next-btn,
    html.ios-shell-root #play-mode-btn,
    html.ios-shell-root #mini-queue-btn {
      width: 40px !important;
      height: 40px !important;
    }
    html.ios-shell-root .lyrics-toggle-btn,
    html.ios-shell-root #volume-control,
    html.ios-shell-root #controls-hide-btn,
    html.ios-shell-root #immersive-btn {
      display: flex !important;
    }
    html.ios-shell-root .fullscreen-toggle-btn,
    html.ios-shell-root #time-display {
      display: flex !important;
      flex: 0 0 auto !important;
    }
    html.ios-shell-root #time-display {
      min-width: 74px !important;
      height: 34px !important;
      font-size: 10px !important;
      padding: 0 4px !important;
      justify-content: center !important;
    }
    html.ios-shell-root .volume-popover,
    html.ios-shell-root .quality-popover {
      bottom: 38px !important;
    }
    html.ios-shell-root .mini-queue-popover {
      width: calc(100vw - 36px) !important;
      max-height: min(380px, calc(100vh - 230px)) !important;
      bottom: calc(100% + 10px) !important;
    }
    html.ios-shell-root #ios-player-toggle {
      position: absolute !important;
      z-index: 4 !important;
      left: 50% !important;
      top: 4px !important;
      width: 44px !important;
      height: 18px !important;
      margin: 0 !important;
      padding: 0 !important;
      transform: translateX(-50%) !important;
      border: 0 !important;
      border-radius: 999px !important;
      background: transparent !important;
      color: rgba(255,255,255,.50) !important;
    }
    html.ios-shell-root #ios-player-toggle span {
      display: block !important;
      width: 38px !important;
      height: 4px !important;
      margin: 7px auto 0 !important;
      border: 0 !important;
      border-radius: 999px !important;
      background: rgba(255,255,255,.42) !important;
      box-shadow: inset 0 1px 0 rgba(255,255,255,.20), 0 1px 4px rgba(0,0,0,.26) !important;
      transform: none !important;
      transition: background .22s, width .22s, opacity .22s !important;
    }
    html.ios-shell-root body.ios-player-expanded #ios-player-toggle span {
      width: 46px !important;
      background: rgba(255,255,255,.60) !important;
    }
    html.ios-shell-root #ios-performance-panel {
      position: fixed;
      z-index: 560;
      top: max(52px, env(safe-area-inset-top) + 22px);
      left: 12px;
      font-family: var(--font-sans);
    }
    html.ios-shell-root #ios-performance-panel .ios-perf-main {
      height: 34px;
      padding: 0 12px;
      border: 1px solid rgba(255,255,255,.12);
      border-radius: 999px;
      background: rgba(0,0,0,.52);
      color: rgba(255,255,255,.78);
      font: inherit;
      font-size: 11px;
      font-weight: 780;
      box-shadow: 0 12px 30px rgba(0,0,0,.28), inset 0 1px 0 rgba(255,255,255,.08);
      backdrop-filter: blur(16px) saturate(1.2);
      -webkit-backdrop-filter: blur(16px) saturate(1.2);
    }
    html.ios-shell-root #ios-performance-panel .ios-perf-main b {
      color: rgba(232,214,168,.94);
      margin-left: 4px;
    }
    html.ios-shell-root #ios-performance-panel .ios-perf-pop {
      position: absolute;
      top: 42px;
      left: 0;
      width: 128px;
      display: none;
      grid-template-columns: 1fr 1fr;
      gap: 6px;
      padding: 8px;
      border-radius: 16px;
      background: rgba(0,0,0,.78);
      border: 1px solid rgba(255,255,255,.12);
      box-shadow: 0 18px 46px rgba(0,0,0,.38);
      backdrop-filter: blur(18px) saturate(1.15);
      -webkit-backdrop-filter: blur(18px) saturate(1.15);
    }
    html.ios-shell-root #ios-performance-panel.open .ios-perf-pop {
      display: grid;
    }
    html.ios-shell-root #ios-performance-panel .ios-perf-pop button {
      min-height: 30px;
      border: 1px solid rgba(255,255,255,.10);
      border-radius: 10px;
      background: rgba(255,255,255,.06);
      color: rgba(255,255,255,.78);
      font: inherit;
      font-size: 11px;
      font-weight: 760;
    }
    html.ios-shell-root #ios-performance-panel .ios-perf-pop [data-ios-power] {
      grid-column: 1 / -1;
      color: #fff0bf;
      border-color: rgba(244,210,138,.32);
      background: rgba(244,210,138,.12);
    }
    html.ios-shell-root body.ios-power-save #canvas-container {
      opacity: .72 !important;
    }
    html.ios-shell-root body.ios-power-save #idle-guide-canvas,
    html.ios-shell-root body.ios-power-save #login-guide-canvas,
    html.ios-shell-root body.ios-power-save #hand-canvas,
    html.ios-shell-root body.ios-power-save #photo-deck {
      display: none !important;
    }
    html.ios-shell-root body.ios-power-save .home-card {
      animation: none !important;
    }
    /* ===== iOS 完整(DIY)模式：控制中枢 + 视觉控制台 + 音源标签 ===== */
    html.ios-shell-root #ios-control-hub {
      position: fixed;
      z-index: 565;
      top: max(52px, env(safe-area-inset-top) + 22px);
      right: 12px;
      font-family: var(--font-sans);
    }
    /* 账号胶囊左移给控制中枢让位，避免与齿轮重叠 */
    html.ios-shell-root #top-right { right: 58px !important; }
    html.ios-shell-root #top-right #home-btn,
    html.ios-shell-root #top-right #settings-btn {
      display: none !important;
    }
    html.ios-shell-root #ios-control-hub .ios-hub-main {
      width: 38px; height: 38px;
      display: flex; align-items: center; justify-content: center;
      border: 1px solid rgba(255,255,255,.14);
      border-radius: 50%;
      background: rgba(0,0,0,.54);
      color: rgba(255,255,255,.84);
      box-shadow: 0 12px 30px rgba(0,0,0,.3), inset 0 1px 0 rgba(255,255,255,.08);
      backdrop-filter: blur(16px) saturate(1.2);
      -webkit-backdrop-filter: blur(16px) saturate(1.2);
    }
    html.ios-shell-root #ios-control-hub .ios-hub-pop {
      position: absolute;
      top: 46px; right: 0;
      width: 196px;
      display: none;
      flex-direction: column;
      gap: 4px;
      padding: 8px;
      border-radius: 16px;
      background: rgba(0,0,0,.84);
      border: 1px solid rgba(255,255,255,.12);
      box-shadow: 0 18px 46px rgba(0,0,0,.44);
      backdrop-filter: blur(18px) saturate(1.15);
      -webkit-backdrop-filter: blur(18px) saturate(1.15);
    }
    html.ios-shell-root #ios-control-hub.open .ios-hub-pop { display: flex; }
    html.ios-shell-root #ios-control-hub .ios-hub-pop button {
      min-height: 42px;
      text-align: left;
      padding: 0 13px;
      border: 1px solid rgba(255,255,255,.08);
      border-radius: 11px;
      background: rgba(255,255,255,.05);
      color: rgba(255,255,255,.88);
      font: inherit; font-size: 13.5px; font-weight: 640;
    }
    html.ios-shell-root #ios-control-hub .ios-hub-pop button#ios-hub-diy.on {
      color: rgba(255,248,226,.96);
      background: linear-gradient(135deg,rgba(244,210,138,.22),rgba(255,255,255,.08));
      border-color: rgba(244,210,138,.34);
      box-shadow: inset 0 1px 0 rgba(255,255,255,.10);
    }
    /* 桌面悬浮 fx 入口在 iOS 隐藏，统一走控制中枢 */
    html.ios-shell-root #fx-fab,
    html.ios-shell-root #fx-fab-hide-btn { display: none !important; }
    /* 视觉控制台：移动端底部抽屉，占满宽度、可滚动 */
    html.ios-shell-root #fx-panel {
      left: 10px !important;
      right: 10px !important;
      width: auto !important;
      max-width: none !important;
      bottom: max(120px, env(safe-area-inset-bottom) + 110px) !important;
      max-height: calc(100vh - 250px) !important;
      z-index: 600 !important;
      border-radius: 22px !important;
    }
    html.ios-shell-root body.ios-player-expanded #fx-panel {
      bottom: max(176px, env(safe-area-inset-bottom) + 166px) !important;
    }
    html.ios-shell-root #fx-panel.show,
    html.ios-shell-root #fx-panel.peek { right: 10px !important; }
    html.ios-shell-root #fx-panel .fx-sub { display: none !important; }
    html.ios-shell-root #hotkey-settings-btn { display: none !important; }
    html.ios-shell-root .ios-panel-close {
      position: absolute;
      top: 12px; right: 12px;
      width: 32px; height: 32px;
      border-radius: 50%;
      border: 1px solid rgba(255,255,255,.16);
      background: rgba(255,255,255,.10);
      color: rgba(255,255,255,.82);
      font-size: 14px; line-height: 1;
      z-index: 6;
      display: flex; align-items: center; justify-content: center;
      backdrop-filter: blur(8px);
      -webkit-backdrop-filter: blur(8px);
    }
    /* 音源标签：可见、可横向滑动 */
    html.ios-shell-root #search-mode-tabs {
      display: flex !important;
      overflow-x: auto !important;
      overflow-y: hidden !important;
      gap: 4px !important;
      scrollbar-width: none !important;
      -webkit-overflow-scrolling: touch !important;
      transform: none !important;
      width: 100% !important;
      padding-bottom: 2px !important;
    }
    html.ios-shell-root #search-mode-tabs::-webkit-scrollbar { display: none !important; }
    html.ios-shell-root #search-mode-tabs button { flex: 0 0 auto !important; }
    /* 设置弹层置于 iOS 层之上 */
    html.ios-shell-root #settings-overlay { z-index: 2000 !important; }
    html.ios-shell-root #settings-modal { width: min(440px, 92vw) !important; max-height: 84vh !important; }
    /* ===== iOS 底部分页 Tab 栏 ===== */
    html.ios-shell-root #ios-tabbar {
      position: fixed;
      left: 0; right: 0; bottom: 0;
      height: calc(58px + env(safe-area-inset-bottom));
      padding-bottom: calc(env(safe-area-inset-bottom) + 4px);
      display: flex;
      z-index: 590;
      background: rgba(8,9,14,.78);
      border-top: 1px solid rgba(255,255,255,.08);
      backdrop-filter: blur(22px) saturate(1.2);
      -webkit-backdrop-filter: blur(22px) saturate(1.2);
    }
    html.ios-shell-root #ios-tabbar button {
      flex: 1;
      display: flex; flex-direction: column; align-items: center; justify-content: center;
      gap: 4px;
      border: 0; background: none;
      color: rgba(255,255,255,.5);
      font-size: 11.5px; font-weight: 660;
      font-family: var(--font-sans);
    }
    html.ios-shell-root #ios-tabbar button svg { width: 24px; height: 24px; }
    html.ios-shell-root #ios-tabbar button.active { color: rgba(232,214,168,.94); }
    /* 播放条上移给 Tab 栏让位 */
    html.ios-shell-root #bottom-bar { bottom: calc(70px + env(safe-area-inset-bottom)) !important; }
    /* 首页内容上移，避免被播放条+Tab 栏遮挡 */
    html.ios-shell-root #empty-home { bottom: max(220px, env(safe-area-inset-bottom) + 206px) !important; }
    html.ios-shell-root body.ios-player-expanded #empty-home { bottom: max(282px, env(safe-area-inset-bottom) + 268px) !important; }
    /* 整体字体调大几号 */
    html.ios-shell-root #search-input { font-size: 15px !important; }
    html.ios-shell-root #search-mode-tabs button { font-size: 12.5px !important; }
    html.ios-shell-root .home-card-title { font-size: 17px !important; }
    html.ios-shell-root .home-card-sub { font-size: 11.5px !important; }
    html.ios-shell-root .home-card-label { font-size: 9.5px !important; }
    html.ios-shell-root .control-title { font-size: 13px !important; }
    html.ios-shell-root .control-artist { font-size: 11.5px !important; }
    html.ios-shell-root .home-sub { font-size: 13.5px !important; }
    html.ios-shell-root #playlist-panel .pl-card-title, html.ios-shell-root #playlist-panel .queue-item-title { font-size: 14.5px !important; }
    /* 歌词层永不吃点击 */
    html.ios-shell-root #stage-lyrics { pointer-events: none !important; }
    /* 浏览页(首页/歌单)：隐藏歌词与照片台，画布略调暗，保持干净不串扰 */
    html.ios-shell-root body.ios-tab-home #stage-lyrics,
    html.ios-shell-root body.ios-tab-playlist #stage-lyrics,
    html.ios-shell-root body.ios-tab-home #photo-deck,
    html.ios-shell-root body.ios-tab-playlist #photo-deck { display: none !important; }
    html.ios-shell-root body.ios-tab-home #canvas-container,
    html.ios-shell-root body.ios-tab-playlist #canvas-container { opacity: 0 !important; }
    /* 首页：强制首页内容常显（覆盖播放时 app 的隐藏），歌单面板隐藏 */
    html.ios-shell-root body.ios-tab-home #empty-home {
      opacity: 1 !important;
      pointer-events: auto !important;
      transform: translateX(-50%) translateY(0) scale(1) !important;
    }
    html.ios-shell-root body.ios-tab-home #playlist-panel { display: none !important; }
    /* 歌单页：面板全宽下移，隐藏首页与搜索框 */
    html.ios-shell-root body.ios-tab-playlist #empty-home,
    html.ios-shell-root body.ios-tab-playlist #search-area { display: none !important; }
    html.ios-shell-root body.ios-tab-playlist #playlist-panel {
      top: max(96px, env(safe-area-inset-top) + 66px) !important;
      left: 10px !important;
      width: calc(100vw - 20px) !important;
      max-height: calc(100vh - 270px) !important;
    }
    html.ios-shell-root #playlist-panel .fx-sub { display: none !important; }
    /* 视觉页：隐藏浏览内容，全开画布+歌词+照片台（Now Playing 沉浸） */
    html.ios-shell-root body.ios-tab-visual #empty-home,
    html.ios-shell-root body.ios-tab-visual #search-area,
    html.ios-shell-root body.ios-tab-visual #playlist-panel { display: none !important; }
    html.ios-shell-root body.ios-tab-home #fullscreen-diy-zone,
    html.ios-shell-root body.ios-tab-home #fx-fab,
    html.ios-shell-root body.ios-tab-home #fx-fab-hide-btn,
    html.ios-shell-root body.ios-tab-playlist #fullscreen-diy-zone,
    html.ios-shell-root body.ios-tab-playlist #fx-fab,
    html.ios-shell-root body.ios-tab-playlist #fx-fab-hide-btn {
      display: none !important;
      opacity: 0 !important;
      pointer-events: none !important;
    }
    html.ios-shell-root body.ios-tab-visual #canvas-container {
      inset: 0 !important;
      width: 100vw !important;
      height: 100vh !important;
    }
    @media (min-width: 700px) {
      html.ios-shell-root #ios-performance-panel {
        top: max(34px, env(safe-area-inset-top) + 18px) !important;
        left: max(18px, env(safe-area-inset-left) + 18px) !important;
      }
      html.ios-shell-root #ios-control-hub {
        top: max(34px, env(safe-area-inset-top) + 18px) !important;
        right: max(18px, env(safe-area-inset-right) + 18px) !important;
      }
      html.ios-shell-root #top-right {
        top: max(34px, env(safe-area-inset-top) + 18px) !important;
        right: max(72px, env(safe-area-inset-right) + 72px) !important;
      }
      html.ios-shell-root #search-area,
      html.ios-shell-root body.simple-mode #search-area {
        width: min(760px, calc(100vw - 72px)) !important;
      }
      html.ios-shell-root #empty-home {
        width: min(900px, calc(100vw - 72px)) !important;
        top: max(136px, env(safe-area-inset-top) + 104px) !important;
        bottom: max(202px, env(safe-area-inset-bottom) + 188px) !important;
        overflow-y: auto !important;
        -webkit-overflow-scrolling: touch !important;
      }
      html.ios-shell-root #playlist-panel {
        left: max(22px, env(safe-area-inset-left) + 22px) !important;
        width: min(520px, calc(100vw - 44px)) !important;
      }
      html.ios-shell-root body.ios-tab-playlist #playlist-panel {
        width: min(760px, calc(100vw - 56px)) !important;
        left: 50% !important;
        transform: translateX(-50%) !important;
        max-height: calc(100vh - 250px) !important;
      }
      html.ios-shell-root #bottom-bar {
        left: 50% !important;
        right: auto !important;
        width: min(720px, calc(100vw - 72px)) !important;
        transform: translateX(-50%) !important;
      }
      html.ios-shell-root #ios-tabbar {
        left: 50% !important;
        right: auto !important;
        width: min(720px, calc(100vw - 72px)) !important;
        transform: translateX(-50%) !important;
        border-radius: 26px 26px 0 0 !important;
        border-left: 1px solid rgba(255,255,255,.08) !important;
        border-right: 1px solid rgba(255,255,255,.08) !important;
      }
    }
    @media (orientation: landscape) {
      html.ios-shell-root body.ios-tab-visual,
      html.ios-shell-root body.ios-landscape-stage {
        overflow: hidden !important;
      }
      html.ios-shell-root body.ios-tab-visual #ios-tabbar,
      html.ios-shell-root body.ios-landscape-stage #ios-tabbar,
      html.ios-shell-root body.ios-tab-visual #bottom-bar,
      html.ios-shell-root body.ios-landscape-stage #bottom-bar,
      html.ios-shell-root body.ios-tab-visual #search-area,
      html.ios-shell-root body.ios-landscape-stage #search-area,
      html.ios-shell-root body.ios-tab-visual #top-right,
      html.ios-shell-root body.ios-landscape-stage #top-right,
      html.ios-shell-root body.ios-tab-visual #ios-performance-panel,
      html.ios-shell-root body.ios-landscape-stage #ios-performance-panel {
        display: none !important;
      }
      html.ios-shell-root body.ios-tab-visual #canvas-container,
      html.ios-shell-root body.ios-landscape-stage #canvas-container {
        inset: 0 !important;
        width: 100vw !important;
        height: 100vh !important;
        opacity: 1 !important;
      }
      html.ios-shell-root body.ios-tab-visual #photo-deck,
      html.ios-shell-root body.ios-landscape-stage #photo-deck {
        transform: translate(-50%, -50%) scale(.82) !important;
      }
      html.ios-shell-root body.ios-tab-visual #stage-lyrics,
      html.ios-shell-root body.ios-landscape-stage #stage-lyrics {
        display: block !important;
        bottom: max(22px, env(safe-area-inset-bottom) + 14px) !important;
        pointer-events: none !important;
      }
      html.ios-shell-root body.ios-tab-visual #ios-control-hub,
      html.ios-shell-root body.ios-landscape-stage #ios-control-hub {
        top: max(12px, env(safe-area-inset-top) + 8px) !important;
        right: max(12px, env(safe-area-inset-right) + 12px) !important;
      }
      html.ios-shell-root body.ios-tab-visual #fx-panel,
      html.ios-shell-root body.ios-landscape-stage #fx-panel {
        left: auto !important;
        right: max(12px, env(safe-area-inset-right) + 12px) !important;
        bottom: max(12px, env(safe-area-inset-bottom) + 12px) !important;
        width: min(430px, 44vw) !important;
        max-height: calc(100vh - 34px) !important;
        border-radius: 18px !important;
      }
    }
    @media (max-width: 430px) {
      html.ios-shell-root #search-area.peek,
      html.ios-shell-root body.simple-mode #search-area.peek,
      html.ios-shell-root body.desktop-shell.simple-mode #search-area.peek {
        top: max(88px, env(safe-area-inset-top) + 62px) !important;
      }
      html.ios-shell-root #search-box { height: 48px !important; border-radius: 18px !important; }
      html.ios-shell-root #bottom-bar { min-height: 96px !important; }
      html.ios-shell-root body.ios-player-expanded #bottom-bar { min-height: 146px !important; }
      html.ios-shell-root #photo-deck { transform: translate(-50%, 0) scale(.96) !important; }
    }

    /* ===== iPhone 17 polish: Apple Music style regions, stable hit targets ===== */
    @media (max-width: 430px) {
      html.ios-shell-root #ios-performance-panel {
        top: max(50px, env(safe-area-inset-top) + 18px) !important;
        left: 14px !important;
      }
      html.ios-shell-root #ios-performance-panel .ios-perf-main {
        height: 32px !important;
        padding: 0 10px !important;
        font-size: 10.5px !important;
      }
      html.ios-shell-root #ios-control-hub {
        top: max(49px, env(safe-area-inset-top) + 17px) !important;
        right: 14px !important;
      }
      html.ios-shell-root #ios-control-hub .ios-hub-main {
        width: 36px !important;
        height: 36px !important;
      }
      html.ios-shell-root #top-right {
        top: max(49px, env(safe-area-inset-top) + 17px) !important;
        right: 56px !important;
        max-width: calc(100vw - 138px) !important;
        transform: none !important;
        display: flex !important;
        gap: 6px !important;
        overflow: hidden !important;
      }
      html.ios-shell-root #top-right > * {
        flex: 0 0 auto !important;
      }
      html.ios-shell-root #top-right .top-account-pill {
        width: 34px !important;
        height: 34px !important;
        min-width: 34px !important;
      }
      html.ios-shell-root #top-right .top-account-pill img {
        width: 28px !important;
        height: 28px !important;
      }
      html.ios-shell-root #search-area.peek,
      html.ios-shell-root body.simple-mode #search-area.peek,
      html.ios-shell-root body.desktop-shell.simple-mode #search-area.peek {
        top: max(88px, env(safe-area-inset-top) + 58px) !important;
      }
      html.ios-shell-root #search-area,
      html.ios-shell-root body.simple-mode #search-area {
        width: calc(100vw - 28px) !important;
        overflow: hidden !important;
      }
      html.ios-shell-root #search-stack {
        flex: 1 1 auto !important;
        min-width: 0 !important;
        width: 100% !important;
      }
      html.ios-shell-root #search-box {
        height: 44px !important;
        border-radius: 16px !important;
      }
      html.ios-shell-root #search-mode-tabs {
        margin-top: 7px !important;
        padding: 0 1px 2px !important;
      }
      html.ios-shell-root #search-mode-tabs button {
        min-height: 28px !important;
        padding: 0 11px !important;
        border-radius: 999px !important;
        font-size: 12px !important;
        line-height: 1 !important;
      }
      html.ios-shell-root #empty-home {
        top: max(144px, env(safe-area-inset-top) + 114px) !important;
        bottom: max(178px, env(safe-area-inset-bottom) + 164px) !important;
        width: calc(100vw - 22px) !important;
        overflow-y: auto !important;
        overflow-x: hidden !important;
        pointer-events: auto !important;
        touch-action: pan-y !important;
        overscroll-behavior-y: contain !important;
        -webkit-overflow-scrolling: touch !important;
        scrollbar-width: none !important;
      }
      html.ios-shell-root #empty-home::-webkit-scrollbar {
        display: none !important;
      }
      html.ios-shell-root body.ios-player-expanded #empty-home {
        bottom: max(238px, env(safe-area-inset-bottom) + 224px) !important;
      }
      html.ios-shell-root .empty-home-shell {
        gap: 10px !important;
        height: auto !important;
        min-height: 0 !important;
        overflow: visible !important;
        overflow-x: hidden !important;
        padding: 0 0 48px !important;
        overscroll-behavior-y: contain !important;
        -webkit-overflow-scrolling: touch !important;
        touch-action: pan-y !important;
      }
      html.ios-shell-root .home-hero {
        min-height: 174px !important;
        padding: 17px 18px !important;
        border-radius: 22px !important;
      }
      html.ios-shell-root .home-title,
      html.ios-shell-root .home-title.home-construction-title {
        font-size: 30px !important;
        max-width: 230px !important;
        letter-spacing: 0 !important;
      }
      html.ios-shell-root .home-sub {
        font-size: 12px !important;
        max-width: 252px !important;
        display: -webkit-box !important;
        -webkit-line-clamp: 2 !important;
        -webkit-box-orient: vertical !important;
        overflow: hidden !important;
      }
      html.ios-shell-root .home-grid {
        grid-template-columns: repeat(2, minmax(0, 1fr)) !important;
        gap: 9px !important;
        align-items: stretch !important;
        padding-bottom: 10px !important;
      }
      html.ios-shell-root .home-card {
        position: relative !important;
        min-height: 108px !important;
        aspect-ratio: auto !important;
        height: 100% !important;
        padding: 12px !important;
        overflow: hidden !important;
      }
      html.ios-shell-root .home-card-title {
        max-width: calc(100% - 56px) !important;
        font-size: 15.5px !important;
        line-height: 1.08 !important;
        letter-spacing: 0 !important;
        display: -webkit-box !important;
        -webkit-line-clamp: 3 !important;
        -webkit-box-orient: vertical !important;
        overflow: hidden !important;
      }
      html.ios-shell-root .home-card-sub {
        max-width: calc(100% - 58px) !important;
        font-size: 10.5px !important;
        line-height: 1.28 !important;
        -webkit-line-clamp: 2 !important;
      }
      html.ios-shell-root .home-card-label {
        font-size: 8.5px !important;
        letter-spacing: .12em !important;
      }
      html.ios-shell-root .home-card-art {
        width: 46px !important;
        height: 46px !important;
        right: 10px !important;
        bottom: 10px !important;
        border-radius: 13px !important;
      }
      html.ios-shell-root #bottom-bar {
        left: 10px !important;
        right: 10px !important;
        bottom: calc(86px + env(safe-area-inset-bottom)) !important;
        min-height: 76px !important;
        max-height: 82px !important;
        padding: 6px 10px 8px !important;
        border-radius: 23px !important;
      }
      html.ios-shell-root body.ios-player-expanded #bottom-bar {
        min-height: 146px !important;
        max-height: 156px !important;
        bottom: calc(86px + env(safe-area-inset-bottom)) !important;
      }
      html.ios-shell-root #progress-bar {
        width: calc(100% - 18px) !important;
        height: 2px !important;
        margin-bottom: 0 !important;
      }
      html.ios-shell-root #controls {
        grid-template-rows: 42px !important;
        gap: 4px !important;
        align-items: center !important;
      }
      html.ios-shell-root body.ios-player-expanded #controls {
        grid-template-rows: 38px 50px 34px !important;
      }
      html.ios-shell-root .control-cover {
        width: 32px !important;
        height: 32px !important;
        border-radius: 9px !important;
      }
      html.ios-shell-root .control-track {
        gap: 8px !important;
      }
      html.ios-shell-root .control-title {
        font-size: 12px !important;
        line-height: 1.15 !important;
        white-space: nowrap !important;
        overflow: hidden !important;
        text-overflow: ellipsis !important;
      }
      html.ios-shell-root .control-artist {
        font-size: 10.5px !important;
        white-space: nowrap !important;
        overflow: hidden !important;
        text-overflow: ellipsis !important;
      }
      html.ios-shell-root .ctrl-btn {
        width: 32px !important;
        height: 32px !important;
        border-radius: 11px !important;
      }
      html.ios-shell-root #play-btn {
        width: 40px !important;
        height: 40px !important;
        border-radius: 14px !important;
      }
      html.ios-shell-root #prev-btn {
        display: none !important;
      }
      html.ios-shell-root body.ios-player-expanded #prev-btn {
        display: flex !important;
      }
      html.ios-shell-root .lyrics-toggle-btn,
      html.ios-shell-root #volume-control,
      html.ios-shell-root #controls-hide-btn,
      html.ios-shell-root #immersive-btn,
      html.ios-shell-root .fullscreen-toggle-btn,
      html.ios-shell-root #time-display {
        display: none !important;
      }
      html.ios-shell-root body.ios-player-expanded .lyrics-toggle-btn,
      html.ios-shell-root body.ios-player-expanded #volume-control,
      html.ios-shell-root body.ios-player-expanded #immersive-btn,
      html.ios-shell-root body.ios-player-expanded .fullscreen-toggle-btn,
      html.ios-shell-root body.ios-player-expanded #time-display {
        display: flex !important;
      }
      html.ios-shell-root #ios-player-toggle {
        top: -1px !important;
        height: 18px !important;
      }
      html.ios-shell-root #ios-tabbar {
        height: calc(58px + env(safe-area-inset-bottom)) !important;
        padding-bottom: calc(env(safe-area-inset-bottom) + 10px) !important;
      }
      html.ios-shell-root #ios-tabbar button {
        gap: 2px !important;
        font-size: 11px !important;
        justify-content: flex-start !important;
        padding-top: 8px !important;
      }
      html.ios-shell-root #ios-tabbar button svg {
        width: 22px !important;
        height: 22px !important;
      }
      html.ios-shell-root body.ios-tab-playlist #playlist-panel {
        top: max(92px, env(safe-area-inset-top) + 62px) !important;
        bottom: calc(166px + env(safe-area-inset-bottom)) !important;
        max-height: none !important;
        overflow-y: auto !important;
        overflow-x: hidden !important;
        -webkit-overflow-scrolling: touch !important;
        touch-action: pan-y !important;
        border-radius: 22px !important;
      }
      html.ios-shell-root body.ios-tab-playlist #queue-list,
      html.ios-shell-root body.ios-tab-playlist #pl-list,
      html.ios-shell-root body.ios-tab-playlist #podcast-list {
        max-height: none !important;
        padding-bottom: 26px !important;
      }
      html.ios-shell-root #fx-panel {
        top: max(94px, env(safe-area-inset-top) + 64px) !important;
        bottom: max(166px, env(safe-area-inset-bottom) + 154px) !important;
        max-height: none !important;
        overflow-y: auto !important;
        -webkit-overflow-scrolling: touch !important;
        touch-action: pan-y !important;
      }
      html.ios-shell-root body.ios-player-expanded #fx-panel {
        bottom: max(226px, env(safe-area-inset-bottom) + 214px) !important;
      }
      html.ios-shell-root #login-modal.show,
      html.ios-shell-root #user-modal.show,
      html.ios-shell-root .modal-mask.show {
        padding: max(18px, env(safe-area-inset-top) + 8px) 12px max(24px, env(safe-area-inset-bottom) + 18px) !important;
        align-items: center !important;
      }
      html.ios-shell-root #login-modal .modal.dual-login-modal,
      html.ios-shell-root #user-modal .modal.dual-user-modal,
      html.ios-shell-root .modal-mask.show .modal {
        max-height: calc(100vh - max(44px, env(safe-area-inset-top) + env(safe-area-inset-bottom) + 34px)) !important;
        overflow-y: auto !important;
        -webkit-overflow-scrolling: touch !important;
      }
    }
  `;
  document.head.appendChild(style);
})();