# Credits & Notices

OpenBar is licensed under the **GNU General Public License v3.0 or later** (see `LICENSE`).

OpenBar is an independent, clean-room project. It was written by observing the
*publicly visible behavior* of menu bar managers and reading the source of the
open-source projects below. It does **not** contain, and was not derived from,
decompiled or disassembled code of any proprietary application, and it uses no
third-party trademarks, icons, or artwork.

## Reference projects

| Project | License | What we learned from it |
|---|---|---|
| [Ice](https://github.com/jordanbaird/Ice) by Jordan Baird | GPL-3.0 | Control-item architecture (separate "hidden" / "always-hidden" dividers), seeding `NSStatusItem Preferred Position` defaults, hover/click-to-show and auto-rehide behaviors. OpenBar is GPL-3.0 so that Ice code *may* be reused in the future; any code copied or adapted from Ice must keep Ice's copyright notice in the file header and be listed here. **v0.1 contains no code copied from Ice.** |
| [Hidden Bar](https://github.com/dwarvesf/hidden) by Dwarves Foundation | MIT | The original "expand a separator status item to push icons off-screen" technique and the ⌘-drag onboarding flow. |
| [Dozer](https://github.com/Mortennn/Dozer) | MPL-2.0 | Same separator technique; hide-on-click / auto-hide UX ideas. No Dozer source files are included (MPL-2.0 is file-level copyleft; if any are ever included they must stay under MPL-2.0). |

## Dependencies

| Package | License | Use |
|---|---|---|
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus | MIT | Global hotkey recording and registration. |

MIT-licensed dependencies are GPL-compatible. Their license texts are shipped
inside the Swift package checkout and must be reproduced in binary
distributions (e.g. an "Acknowledgements" file in the app bundle) — TODO before
the first public release.

## Trademarks

macOS is a trademark of Apple Inc. All other product names mentioned in
documentation are the property of their respective owners and are used only
for identification. OpenBar is not affiliated with or endorsed by any of them.
