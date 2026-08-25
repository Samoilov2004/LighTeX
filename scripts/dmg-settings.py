import os


application = os.path.abspath(defines["app"])
application_name = os.path.basename(application)

files = [application]
symlinks = {"Applications": "/Applications"}
icon_locations = {
    application_name: (190, 225),
    "Applications": (530, 225),
}

background = os.path.abspath(defines["background"])
icon = os.path.abspath(defines["volume_icon"])
window_rect = ((100, 100), (720, 440))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 0

arrange_by = None
icon_size = 128
text_size = 13
label_pos = "bottom"
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False

format = "UDZO"
filesystem = "HFS+"
compression_level = 9
