# Layout of the Polka.dmg window, for dmgbuild (https://dmgbuild.readthedocs.io).
# dmgbuild writes the Finder view settings itself, so no Finder scripting is
# needed and it works on CI runners. Called by scripts/package.sh:
#   dmgbuild -s scripts/dmg/settings.py -D app=<Polka.app> -D background=<tiff> Polka <out.dmg>
import os.path

application = defines["app"]  # noqa: F821 (provided by dmgbuild)
appname = os.path.basename(application)

format = "UDZO"
filesystem = "HFS+"
size = None
files = [application]
symlinks = {"Applications": "/Applications"}

# 660×400 background (with a 2× version); icons sit on the arrow's ends.
background = defines["background"]  # noqa: F821
window_rect = ((200, 140), (660, 428))
icon_size = 128
text_size = 13
label_pos = "bottom"
icon_locations = {appname: (170, 190), "Applications": (490, 190)}

default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
arrange_by = None
