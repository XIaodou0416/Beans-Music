# Bilibili native implementation

Reference review: PiliPlus at acff988f18adce44fb0ff870ad50e4da1c78db19 and cilicili at c61b0d33966c5d8e87ea20527b8ba48c702c10c1. Both are GPL-3.0 repositories. This change implements the required behavior in new Beans code rather than importing or translating their source implementations.

UI structure: double-column home feed; stable system video surface; summary/comments switch; horizontal interaction row; UP profile with submissions/collections tabs; collection detail list; original music player retained for listen mode. Mode selection is located in the Bilibili account card.

Core scope: native playback, public video/search/UP/collection/live data, user-triggered like/coin/favorite/follow/comment actions, comment threads, pull refresh, pagination and an iPad keyboard-layout fix. This is not feature parity with either complete client (for example full live chat and advanced danmaku are outside this core implementation).

Verification: CI compiles the iOS app and runs request parsing/window-layout regression checks. Public read endpoints are smoke-tested without account writes. Account actions and device gestures need signed-in physical-device validation. A -352 response from UP submissions is surfaced as an error, not converted to an empty list or sent to a browser.
