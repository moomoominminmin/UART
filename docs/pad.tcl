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

set CHIP_W 1705
set CHIP_H 1705

# The widest pad is 149 um. A 160 um pitch leaves an 11 um gap
# between consecutive 149 um placement boxes.
set PAD_PITCH 160

array set PAD_ORIENTATION {
    south north
    east  flip_east
    north south
    west  flip_west
}


############################################################
# 3. EDGE_MAP  --  EDIT/VERIFY HERE.
#
# set_pad_constraint's -edge takes an integer 0-3, same
# convention family as set_pin_constraints' -edge (where we
# confirmed 0 works without error earlier, but never confirmed
# the full 0-3 mapping to south/east/north/west).
#
# *** VERIFY this mapping before trusting the generated script:
#     place ONE pad with a given -edge value, check which side
#     it actually lands on in the Chip window, and correct the
#     mapping below if needed. ***
############################################################

array set EDGE_MAP {
    south 0
    east  1
    north 2
    west  3
}


############################################################
# 4. PAD_SLOT_MAP  --  EDIT HERE: assign a pad type and a real
#    instance name to each of the 28 slots you want to use.
#    Leave a slot out of this array entirely to leave it
#    unused/spare. Net connectivity is NOT set here -- wire
#    each instance's pins to the right nets directly in the
#    Verilog wrapper (accumulator_8bit_padded) instead; these
#    instance names must match exactly what's in that netlist.
#
# Key format: "side,idx"  where idx runs -3..3 (0 = center pad,
#             matching the measured SIDE_CENTER origin for that side)
# Value format: {pad_type instance_name}
#             instance_name: the actual pad cell instance in your
#                       Verilog netlist that set_pad_constraint
#                       -cells will target for placement.
#
# EXAMPLE STARTER MAPPING (18 signal pins + vdd + vss = 20 of 28 slots)
# *** replace pad_type / instance_name choices below with your
#     real instantiated pad cells ***
############################################################

array set PAD_SLOT_MAP {}



set PAD_SLOT_MAP(south,-3) {PIC u_pad_clk}
set PAD_SLOT_MAP(south,-2) {PIC u_pad_rst_n}
set PAD_SLOT_MAP(south,-1) {PIC u_pad_wr_en}	
set PAD_SLOT_MAP(south,0)  {PIC u_pad_wr_data0}
set PAD_SLOT_MAP(south,1)  {PIC u_pad_wr_data1}
set PAD_SLOT_MAP(south,2)  {PIC u_pad_wr_data2}
set PAD_SLOT_MAP(south,3)  {PIC u_pad_wr_data3}

# --- West edge ---
set PAD_SLOT_MAP(west,-3)  {PVDD u_pad_vdd}
set PAD_SLOT_MAP(west,-2)  {PVSS u_pad_vss}
set PAD_SLOT_MAP(west,-1)  {PIC u_pad_wr_data4}
set PAD_SLOT_MAP(west,0)  {PIC u_pad_wr_data5}
set PAD_SLOT_MAP(west,1)  {PIC u_pad_wr_data6}
set PAD_SLOT_MAP(west,2)  {PIC u_pad_wr_data7}
set PAD_SLOT_MAP(west,3)  {PIC u_pad_rd_en}


# --- North edge ---
set PAD_SLOT_MAP(north,-3)  {PIC u_pad_rx}
set PAD_SLOT_MAP(north,-2)  {POB4 u_pad_tx_full}
set PAD_SLOT_MAP(north,-1)  {POB4 u_pad_tx}
set PAD_SLOT_MAP(north,0)  {POB4 u_pad_rd_data0}
set PAD_SLOT_MAP(north,1)  {POB4 u_pad_rd_data1}
set PAD_SLOT_MAP(north,2)  {POB4 u_pad_rd_data2}
set PAD_SLOT_MAP(north,3)   {POB4 u_pad_rd_data3}

# --- East edge ---
set PAD_SLOT_MAP(east,-3)  {POB4 u_pad_rd_data4}
set PAD_SLOT_MAP(east,-2)  {POB4 u_pad_rd_data5}
set PAD_SLOT_MAP(east,-1)   {POB4 u_pad_rd_data6}
set PAD_SLOT_MAP(east,0)   {POB4 u_pad_rd_data7}
set PAD_SLOT_MAP(east,1)  {POB4 u_pad_rx_empty}
set PAD_SLOT_MAP(east,2)   {POB4 u_pad_rx_overrun}
set PAD_SLOT_MAP(east,3)   {POB4 u_pad_tx_empty}



############################################################
# GENERATOR CODE  --  do not need to edit below this line
############################################################

# Return (side, idx, ox, oy, orient) for each occupied slot.
# Coordinates are the lower-left of the oriented placement box,
# as in the original Nitro pad constraints.
proc generate_pad_positions {} {
    global CHIP_W CHIP_H PAD_PITCH PAD_ORIENTATION PAD_SLOT_MAP pad_geom
    set positions {}

    for {set i -3} {$i <= 3} {incr i} {
        foreach side {south north east west} {
            set key "$side,$i"
            if {![info exists PAD_SLOT_MAP($key)]} { continue }

            set pad_type [lindex $PAD_SLOT_MAP($key) 0]
            set geom $pad_geom($pad_type)
            # Multi-pin entries start with W H. Single-pin entries
            # store the local pin coordinates before W H.
            if {[llength $geom] == 3} {
                lassign $geom width height
            } else {
                lassign [lrange $geom 2 3] width height
            }

            set x [expr {($CHIP_W - $width) / 2.0 + $i * $PAD_PITCH}]
            set y [expr {($CHIP_H - $width) / 2.0 + $i * $PAD_PITCH}]
            switch $side {
                south { set y 0 }
                north { set y [expr {$CHIP_H - $height}] }
                east  { set x [expr {$CHIP_W - $height}] }
                west  { set x 0 }
            }
            lappend positions [list $side $i $x $y $PAD_ORIENTATION($side)]
        }
    }
    return $positions
}


############################################################
# PATHWAY A (native): set_pad_constraint generation
############################################################

# Build one Nitro pad constraint per occupied slot.
proc generate_all_pad_constraints {} {
    global PAD_SLOT_MAP
    set commands {}

    foreach entry [generate_pad_positions] {
        lassign $entry side idx ox oy orient
        set instance_name [lindex $PAD_SLOT_MAP($side,$idx) 1]
        set x_a [expr {round($ox * 10000)}]
        set y_a [expr {round($oy * 10000)}]

        lappend commands [list set_pad_constraint -cells [list $instance_name] -x_origin ${x_a}a -y_origin ${y_a}a -orientation $orient -force true]
    }
    return $commands
}

# Single-line-callable entry point for use inside run_paced_script
# (which evaluates the flow file one line at a time). Run
# place_pads yourself afterward once constraints are set.
proc apply_pad_constraints {} {
    foreach cmd [generate_all_pad_constraints] {
        puts ">>> $cmd"
        eval $cmd
    }
}

# Print-only helper for reviewing generated commands without
# actually running them.
proc preview_pad_constraints {} {
    foreach cmd [generate_all_pad_constraints] {
        puts $cmd
    }
}


############################################################
# PATHWAY B (legacy): pin-coordinate math helpers
# Kept for reference / cross-checking pathway A's results.
############################################################

# Rotation transform: local pin offset (lx,ly) within a cell of
# size (W,H) instanced at (ox,oy) with the given orientation ->
# absolute (x,y). Rotation-only (no mirrored orientations).
proc pad_pin_absolute {lx ly W H ox oy orient} {
    switch $orient {
        north {set ax [expr {$ox + $lx}];      set ay [expr {$oy + $ly}]}
        south {set ax [expr {$ox + $W - $lx}]; set ay [expr {$oy + $H - $ly}]}
        east  {set ax [expr {$ox + $H - $ly}]; set ay [expr {$oy + $lx}]}
        west  {set ax [expr {$ox + $ly}];      set ay [expr {$oy + $W - $lx}]}
        default {error "pad_pin_absolute: unknown orientation '$orient'"}
    }
    return [list $ax $ay]
}

# Look up {lx ly W H layer pw pl} for a given pad type + pin name
# ("" for single-pin types).
proc get_pin_geom {pad_type pin_name} {
    global pad_geom
    if {$pin_name ne "" && [info exists pad_geom($pad_type,$pin_name)]} {
        lassign $pad_geom($pad_type) W H layer
        lassign $pad_geom($pad_type,$pin_name) lx ly pw pl
    } else {
        lassign $pad_geom($pad_type) lx ly W H layer pw pl
    }
    return [list $lx $ly $W $H $layer $pw $pl]
}

# Snap a coordinate (microns) to the routing track grid
# (start 15000a, step 30000a). Returns angstroms.
proc snap_to_track {coord_um} {
    set coord_a [expr {$coord_um * 10000}]
    set snapped [expr {round(($coord_a - 15000) / 30000.0) * 30000 + 15000}]
    return $snapped
}
