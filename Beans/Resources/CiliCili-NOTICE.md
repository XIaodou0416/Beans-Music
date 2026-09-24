# CiliCili in Beans Music

Copyright: Rone89 and the CiliCili contributors.
Upstream: https://github.com/Rone89/cilicili
Revision: c61b0d33966c5d8e87ea20527b8ba48c702c10c1 (2026-09-15)
License: GNU General Public License version 3 only (GPL-3.0-only).
The full, unmodified license is included as CiliCili-LICENSE.txt.

On 2026-09-25 the entire upstream Swift source tree was copied into
Modules/CiliCili/Sources. The former Beans video/detail/comments/player,
uploader, live, search and login screens were removed, not used as fallbacks.

Beans modifications: embedded framework build target; app-entry exclusion;
top channel navigation to retain Beans' bottom tabs; music playback and
account bridges; secure Keychain-only storage; music-only comment host.
The video detail UIKit shell, player, rich comment/reply/composer views,
recommendations, search, dynamic feed, live and uploader implementations
come from the copied source, not screenshot-derived recreations.

Corresponding source:
https://github.com/XIaodou0416/Beans-Music/tree/codex/build-bilibili-detail-20260924
Each Actions run identifies the exact commit and includes a matching
Beans-CiliCili-source artifact with all source, licenses and build files.
Build instructions: Modules/CiliCili/PORTING.md.
This combined distribution is under GPL-3.0-only; original MIT notices
for Beans and other third parties remain preserved. No GitHub Release
is published for this test build.
