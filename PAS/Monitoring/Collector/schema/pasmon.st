#
# Primary Recovery Area
b .
#
# After-Image Area
a .
a .
a .
#
# Schema Area (System Tables)
# Use 64 for 8K DB Block Sizes
d "Schema Area":6,64;1 .
#
# Default Data Area for Application
d "Data Area":10,256;8 .
#
# Default Index Area for Application
d "Index Area":20,32;8 .
#
# Default LOB Area for Application
d "LOB Area":30,32;8 .
