############################################################
# pad_geom_and_place_lib.tcl
#
# Pad frame geometry + placement library for the TEST.LEF pad set.
#
# Connectivity (which pad pin ties to which net) is handled
# directly in the Verilog wrapper netlist (accumulator_8bit_padded),
# NOT in this file -- read_verilog already establishes that wiring
# when the netlist is parsed. This file only handles PLACEMENT:
# positioning each pad cell instance at its correct frame location.
#
# Two placement pathways are provided:
#
#   A) NATIVE (recommended, now that real pad LEFs exist):
#      generate_all_pad_constraints -> set_pad_constraint calls,
#      placing whole pad cell instances via Nitro-SoC's own
#      pad-ring machinery (-x_origin/-y_origin/-orientation),
#      then call place_pads to finalize.
#
#   B) LEGACY (pin-coordinate math, from before real LEFs existed):
#      pad_pin_absolute/get_pin_geom/snap_to_track helpers, for
#      placing raw edge pins on the core using measured per-pad-
#      type pin offsets + rotation math. Kept here for reference /
#      cross-checking pathway A's results if needed. No generator
#      proc is wired up for this path currently -- see earlier
#      chat history if you need to regenerate one.
#
# USAGE (from accumulator_flow.tcl), pathway A:
#   source pad_geom_and_place_lib.tcl
#   apply_pad_constraints
#   place_pads
#
# EDIT ZONES (marked below):
#   1. pad_geom array       - pad sizes and measured pin geometry
#   2. FRAME MEASUREMENTS   - chip size, pad pitch and orientations
#   3. EDGE_MAP             - side name -> Nitro-SoC -edge integer (VERIFY!)
#   4. PAD_SLOT_MAP         - which pad type/instance goes at each slot
############################################################


############################################################
# 1. PAD_GEOM  --  EDIT HERE if you add/change pad types or
#    remeasure pin offsets. Native placement uses W and H from this
#    table. The legacy helpers also use the pin rectangles below.
#
# Single-pin types:   pad_geom(TYPE)          {lx ly W H layer pw pl}
# Multi-pin types:    pad_geom(TYPE)          {W H layer}
#                     pad_geom(TYPE,PINNAME)  {lx ly pw pl}
#
# All units in microns (u), measured relative to each pad's own
# placement bounding-box lower-left corner (pr_boundary / ESD
# corner), with that corner at local (0,0).
############################################################

array set pad_geom {}

# TEST.LEF internal connection rectangles: PIC/Y, POB4/A, PVDD/VDD
# (MET2), PVSS/VSS (MET2), and PANA/PAD and PADR (MET2).
# Negative offsets and pin shapes outside SIZE are preserved as drawn.
# PBCT4, PBCT8, POB8 and POB24 retain legacy values and are absent
# from TEST.LEF. Supply their updated macros before placing those types.

set pad_geom(PIC) {-9.08 182.94 144 186 MET1 2 2.77}

set pad_geom(PBCT4)    {122 344.5 MET2}
set pad_geom(PBCT4,OE) {3.55 343.1 3.2 1.4}
set pad_geom(PBCT4,A)  {18.2 343.1 3.2 1.4}
set pad_geom(PBCT4,Y)  {114 343.1 3.2 1.4}

set pad_geom(PBCT8)    {122 344.5 MET2}
set pad_geom(PBCT8,OE) {3.55 343.1 3.2 1.4}
set pad_geom(PBCT8,A)  {18.2 343.1 3.2 1.4}
set pad_geom(PBCT8,Y)  {114 343.1 3.2 1.4}

set pad_geom(POB4)  {-9.14 183.2 149 186 MET2 2 2.45}
set pad_geom(POB8)  {6 343.1 122 344.5 MET2 3.2 1.4}
set pad_geom(POB24) {27.1 343.1 122 344.5 MET2 3.2 1.4}

set pad_geom(PANA)       {136 186 MET2}
set pad_geom(PANA,PADR)  {87.04 185.16 27.6 1.15}
set pad_geom(PANA,PAD)   {3.4 184.19 34 1.09}

set pad_geom(PVDD) {25.8 184.67 121 189 MET2 68.4 3.83}
set pad_geom(PVSS) {12.6 185.06 96 189 MET2 94.8 4.04}


############################################################
# 2. FRAME MEASUREMENTS
#
# Chip coordinates in microns, from create_chip in the Nitro script.
# Preserve the core region (344.5,344.5)-(1360.5,1360.5).
# Put pad bounding boxes against the die perimeter and center each
# slot on its pitch location. The current corner locations need
# separate adjustment: 7 x 149 um cannot fit in a 1016 um corner gap.
############################################################
