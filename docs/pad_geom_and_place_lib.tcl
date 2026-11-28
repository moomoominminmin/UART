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
# USAGE (from etri050_nitro_script_test.tcl), pathway A:
#   source pad_geom_and_place_lib.tcl     ;# BEFORE create_chip (sets CHIP_SIZE)
#   apply_corner_constraints              ;# 4 x PCORNER, ring-aligned
#   apply_pad_constraints
#   place_pads
#   report_pad_ring_gaps                  ;# optional, prints ring holes
#
# 2026-11-28: corners moved from create_corner_cells to explicit
# set_pad_constraint (ring-aligned at 91.5 um inset). Die size and
# pad slots unchanged (fixed MPW frame).
#
# EDIT ZONES (marked below):
#   1. pad_geom array       - pad sizes and measured pin geometry
#   2. FRAME MEASUREMENTS   - chip size, corner inset, orientations
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
# 1b. PAD_BODY / PAD_RING  (measured from TEST.LEF, all layers)
#
# Along-edge extents in the pad's own local x (north orientation),
# relative to the LEF SIZE box lower-left (0,0).
#   pad_body(TYPE) {lo hi} : every drawn shape (ESD devices etc.)
#   pad_ring(TYPE) {lo hi} : MET3 VDD/VSS ring strips
# PIC/POB4 carry ESD devices hanging LEFT of the SIZE box
# (to -21.08 / -26.07); used by the ring-gap report.
############################################################

array set pad_body {
    PIC   {-21.08 123.35}
    POB4  {-26.07 123.10}
    PVDD  {-0.60  120.60}
    PVSS  {12.00  108.00}
    PANA  {-7.36  129.48}
}
array set pad_ring {
    PIC   {-4.85  123.10}
    POB4  {-5.30  123.10}
    PVDD  {-0.60  120.60}
    PVSS  {12.00  108.00}
    PANA  {-7.35  129.48}
}


############################################################
# 2. FRAME MEASUREMENTS  (microns)
#
# MPW frame is FIXED: die 1705 x 1705, pad slots at a 160 um pitch
# centered on each edge (same positions as before).
#
# Pad-ring geometry from TEST.LEF (same for every pad type):
#   VDD ring (MET3)  depth  91.50 .. 121.10 from the die edge
#   VSS ring (MET3)  depth 139.89 .. 169.49 from the die edge
# PCORNER draws its outer strip at local 0 and inner strip at
# local 48.39, so the corner must sit RING_INSET = 91.5 um in from
# both die edges (create_corner_cells put it at ~40 um: 51 um off).
#
# The end pads start 298 um from the die edge, so the corner's
# LEF box is 200 x 200 (91.5 .. 291.5). Its MET3 arms still reach
# 343 um and overlap the end pads' MET3 rings (same nets), so the
# corner-to-pad ring is continuous without fillers. The corner's
# MET1/MET2/VIA arms would short to the pads' Y/A pins -> removed.
############################################################

set CHIP_SIZE   1705
set CHIP_W      $CHIP_SIZE
set CHIP_H      $CHIP_SIZE
set PAD_PITCH   160

set RING_INSET  91.5
set CORNER_SIZE 200
set CORNER_END  [expr {$RING_INSET + $CORNER_SIZE}]   ;# 291.5 (LEF box)
set CORNER_RING_REACH [expr {$RING_INSET + 251.5}]    ;# 343.0 (MET3 arm end)

# Core region edge (unchanged from the original 1705 flow: 344.5)
set CORE_LO     344.5
set CORE_HI     [expr {$CHIP_SIZE - $CORE_LO}]

array set PAD_ORIENTATION {
    south north
    east  flip_east
    north south
    west  flip_west
}

# Corner instances (must exist in uart_top_ver2_padded.v as
#   PCORNER u_corner_ll (); ... see README in chat).
# Orientation keeps the outer (VDD) strip toward the die corner.
array set CORNER_MAP {
    ll {u_corner_ll north}
    lr {u_corner_lr flip_north}
    ul {u_corner_ul flip_south}
    ur {u_corner_ur south}
}

# Angstrom helper for the main flow script (Nitro "a" units)
proc um2a {um} { return [expr {round($um * 10000)}] }


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

# Pads on one side, ordered by slot index -3..3 (low -> high
# coordinate along the edge, same meaning as before).
proc side_pads {side} {
    global PAD_SLOT_MAP
    set out {}
    for {set i -3} {$i <= 3} {incr i} {
        if {[info exists PAD_SLOT_MAP($side,$i)]} {
            lappend out [list $i {*}$PAD_SLOT_MAP($side,$i)]
        }
    }
    return $out
}

proc pad_wh {pad_type} {
    global pad_geom
    set geom $pad_geom($pad_type)
    if {[llength $geom] == 3} { lassign $geom w h } else { lassign [lrange $geom 2 3] w h }
    return [list $w $h]
}

# Along-edge mirror? (north side = R180, east side = flip_east)
proc side_mirrored {side} { return [expr {$side eq "north" || $side eq "east"}] }

# Local along-edge interval -> global along-edge interval, for a
# pad whose SIZE box starts at global coordinate 'box'.
proc local_to_global {side box w lo hi} {
    if {[side_mirrored $side]} {
        return [list [expr {$box + $w - $hi}] [expr {$box + $w - $lo}]]
    }
    return [list [expr {$box + $lo}] [expr {$box + $hi}]]
}

# Fixed MPW slots: SIZE box centered on its 160 um pitch location.
# Returns list of {idx type inst box_start body_lo body_hi}
# (box_start / body_* are along-edge global coordinates).
proc layout_side {side} {
    global CHIP_SIZE PAD_PITCH pad_body
    set out {}
    foreach p [side_pads $side] {
        lassign $p idx type inst
        lassign [pad_wh $type] w h
        set box [expr {($CHIP_SIZE - $w) / 2.0 + $idx * $PAD_PITCH}]
        lassign $pad_body($type) blo bhi
        lassign [local_to_global $side $box $w $blo $bhi] g0 g1
        lappend out [list $idx $type $inst $box $g0 $g1]
    }
    return $out
}

# Sanity check: corner box / MET1-MET2 must not reach the end pads.
proc check_corner_clearance {} {
    global CHIP_SIZE CORNER_END
    foreach side {south west north east} {
        set e [layout_side $side]
        if {$e eq ""} continue
        set first [lindex $e 0]; set last [lindex $e end]
        set lo [lindex $first 3]
        lassign [pad_wh [lindex $last 1]] w h
        set hi [expr {[lindex $last 3] + $w}]
        set m [expr {min($lo, $CHIP_SIZE - $hi) - $CORNER_END}]
        puts [format "%-5s corner box -> nearest pad box: %6.2f um" $side $m]
        if {$m < 0} { error "corner box overlaps $side end pad by [expr {-$m}] um" }
    }
}

# Return (side, idx, ox, oy, orient) for each occupied slot.
# ox/oy = lower-left of the oriented SIZE box (as before).
proc generate_pad_positions {} {
    global CHIP_W CHIP_H PAD_ORIENTATION
    set positions {}
    foreach side {south north east west} {
        foreach e [layout_side $side] {
            lassign $e idx type inst box
            lassign [pad_wh $type] w h
            switch $side {
                south { set x $box; set y 0 }
                north { set x $box; set y [expr {$CHIP_H - $h}] }
                west  { set x 0;    set y $box }
                east  { set x [expr {$CHIP_W - $h}]; set y $box }
            }
            lappend positions [list $side $idx $x $y $PAD_ORIENTATION($side)]
        }
    }
    return $positions
}

proc generate_corner_positions {} {
    global CHIP_SIZE RING_INSET CORNER_SIZE CORNER_MAP
    set lo $RING_INSET
    set hi [expr {$CHIP_SIZE - $RING_INSET - $CORNER_SIZE}]
    set out {}
    foreach {key x y} [list ll $lo $lo  lr $hi $lo  ul $lo $hi  ur $hi $hi] {
        lassign $CORNER_MAP($key) inst orient
        lappend out [list $key $inst $x $y $orient]
    }
    return $out
}


############################################################
# PATHWAY A (native): set_pad_constraint generation
############################################################

proc generate_all_pad_constraints {} {
    global PAD_SLOT_MAP
    set commands {}
    foreach entry [generate_pad_positions] {
        lassign $entry side idx ox oy orient
        set instance_name [lindex $PAD_SLOT_MAP($side,$idx) 1]
        lappend commands [list set_pad_constraint -cells [list $instance_name] \
            -x_origin [um2a $ox]a -y_origin [um2a $oy]a -orientation $orient -force true]
    }
    return $commands
}

proc generate_corner_constraints {} {
    set commands {}
    foreach entry [generate_corner_positions] {
        lassign $entry key inst x y orient
        lappend commands [list set_pad_constraint -cells [list $inst] \
            -x_origin [um2a $x]a -y_origin [um2a $y]a -orientation $orient -force true]
    }
    return $commands
}

# Single-line-callable entry points (run_paced_script friendly).
proc apply_pad_constraints {} {
    check_corner_clearance
    foreach cmd [generate_all_pad_constraints] { puts ">>> $cmd"; eval $cmd }
}
proc apply_corner_constraints {} {
    foreach cmd [generate_corner_constraints] { puts ">>> $cmd"; eval $cmd }
}
proc preview_pad_constraints {} {
    foreach cmd [concat [generate_corner_constraints] [generate_all_pad_constraints]] { puts $cmd }
}


############################################################
# Ring continuity report (pure Tcl, no Nitro needed)
#
# For each side, walks the MET3 ring from corner to corner and
# prints every hole, marking whether a ring filler can reach it:
#   FILL  : hole lies outside every SIZE box -> IOX filler covers it
#   BLOCK : hole lies inside a pad SIZE box  -> no filler can go
#           there; the pad layout's ring must be extended
############################################################

proc report_pad_ring_gaps {} {
    global CHIP_SIZE CORNER_RING_REACH pad_ring
    foreach side {south west north east} {
        set segs {}     ;# {lo hi what}
        set boxes {}
        lappend segs [list 0 $CORNER_RING_REACH corner]
        lappend segs [list [expr {$CHIP_SIZE - $CORNER_RING_REACH}] $CHIP_SIZE corner]
        foreach e [layout_side $side] {
            lassign $e idx type inst box
            lassign [pad_wh $type] w h
            lassign $pad_ring($type) rlo rhi
            lassign [local_to_global $side $box $w $rlo $rhi] g0 g1
            lappend segs [list $g0 $g1 $inst]
            lappend boxes [list $box [expr {$box + $w}]]
        }
        set segs [lsort -real -index 0 $segs]
        puts "---- $side ----"
        set reach [lindex $segs 0 1]
        set fill 0.0; set block 0.0
        foreach s [lrange $segs 1 end] {
            lassign $s lo hi what
            if {$lo > $reach + 0.005} {
                # split hole into part inside boxes vs free
                set inbox 0.0
                foreach b $boxes {
                    lassign $b b0 b1
                    set o [expr {min($lo,$b1) - max($reach,$b0)}]
                    if {$o > 0} { set inbox [expr {$inbox + $o}] }
                }
                set free [expr {$lo - $reach - $inbox}]
                puts [format "  hole %8.2f .. %8.2f  (%6.2f um)  FILL %6.2f  BLOCK %6.2f  before %s" \
                    $reach $lo [expr {$lo-$reach}] $free $inbox $what]
                set fill [expr {$fill + $free}]; set block [expr {$block + $inbox}]
            }
            if {$hi > $reach} { set reach $hi }
        }
        puts [format "  total: fillable %.2f um, blocked %.2f um" $fill $block]
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
