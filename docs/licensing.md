# Licensing and attribution

mpv-chameleon is licensed under the **GNU General Public License, version 3 or
(at your option) any later version** (`GPL-3.0-or-later`). The project owner
approved this license and public publication on 2026-10-10.

Copyright (c) 2026 mpv-chameleon contributors. The license covers the original
code, tests, installation tools, examples and documentation in this repository.
See [LICENSE](../LICENSE) for the complete GPLv3 text; the notices in this project
explicitly permit later versions. The software is provided without warranty.

## Permissions and obligations

Commercial use and sale are permitted. There is no additional requirement to
obtain the project owner's permission for resale. Distribution must comply with
the GPL, including applicable license/copyright notices and corresponding-source
requirements. Recipients retain the GPL rights to modify and redistribute the
covered work. See the [GNU GPL FAQ](https://www.gnu.org/licenses/gpl-faq.en.html).

Contributions use the same license; see [CONTRIBUTING](../CONTRIBUTING.md).

## Provenance and dependencies

The Lua implementation was developed from the user's supplied/locally inspected
prototype and substantially reworked for this project. The Swift model, helper,
installer, uninstaller, tests and repository prose were written for this project.
No substantial upstream source files are bundled. The display-identity format
was verified against mpv's public implementation; this project independently
constructs the matching string from documented platform APIs.

mpv and libplacebo remain separately distributed dependencies under their own
licenses. mpv is GPL version 2 or later by default, with an LGPL build option;
GPL-3.0-or-later is compatible with the GPLv3 option of that distribution. This
project does not rely on an exception for proprietary or resale-restricted Lua
scripts. See [mpv's licensing](https://github.com/mpv-player/mpv/blob/v0.41.0/Copyright)
and [GNU license compatibility](https://www.gnu.org/licenses/license-list.html).

Apple frameworks and the Swift toolchain are used on the user's Mac and are not
redistributed. The release ships source and compiles the helper during local
installation. No third-party shader, font, film, test clip, screenshot or copied
user configuration is included. Private integration logs and research downloads
are excluded from releases.

This license does not relicense mpv, libplacebo, Apple components or user media.
Thanks to the mpv and libplacebo communities for the rendering and scripting
infrastructure. No official affiliation or endorsement is claimed.
