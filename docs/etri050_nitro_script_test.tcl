read_lef /mnt/NewHDD/home/vlsiadmin/TannerEDA/TannerTools_v2021.2/Process/Etri_500nm/pdk_digital/LEF/etri050_tech.lef
read_lef /mnt/NewHDD/home/vlsiadmin/TannerEDA/TannerTools_v2021.2/Process/Etri_500nm/pdk_digital/LEF/etri050_std.lef
read_lef /mnt/NewHDD/home/lab_2022104219/sch_folder/LEF_1124/TEST.LEF

read_library /mnt/NewHDD/home/vlsiadmin/TannerEDA/TannerTools_v2021.2/Process/Etri_500nm/pdk_digital/LIB/etri050_std_tt.lib
read_library /mnt/NewHDD/home/vlsiadmin/TannerEDA/TannerTools_v2021.2/Process/Etri_500nm/pdk_digital/LIB/etri050_io_characterized.lib
read_library /mnt/NewHDD/home/vlsiadmin/TannerEDA/TannerTools_v2021.2/Process/Etri_500nm/pdk_digital/PTF/etri050.ptf



read_verilog /mnt/NewHDD/home/lab_2022104219/CPU/uart_top_ver2/uart_top_ver2_synth.v
read_verilog /mnt/NewHDD/home/lab_2022104219/CPU/uart_top_ver2/uart_top_ver2_padded.v

# pad/corner frame library: defines CHIP_SIZE, CORE_LO/CORE_HI, um2a.
# Must be sourced BEFORE create_chip (all coordinates below come from it).
source /mnt/NewHDD/home/lab_2022104219/CPU/pad_geom_and_place_lib.tcl

#run after pause
create_chip -xl_area 0a -yb_area 0a -xr_area ${::CHIP_SIZE}u -yt_area ${::CHIP_SIZE}u -core_site core -xl_margin 0a -yt_margin 0a -orient north -double_backed true -gap 0a

#run after pause
#define region for the core which was instanced as i0 in accumulator_8bit_padded.v
create_floorplan_regions -hiers {i1} -shape [list [um2a $::CORE_LO] [um2a $::CORE_LO] [um2a $::CORE_HI] [um2a $::CORE_LO] [um2a $::CORE_HI] [um2a $::CORE_HI] [um2a $::CORE_LO] [um2a $::CORE_HI]] -core_cell_util 70
#write_session -directory db/create_floorplan_regions_session
#run after pause

stack_macros

create_power_domain -domain primary -include_scope true
create_supply_port VDD -domain primary -direction in
create_supply_port VSS -domain primary -direction in
create_supply_net -net_name VSS -domain primary -power_net false -convert true
create_supply_net -net_name VDD -domain primary -power_net true -convert true
set_domain_supply_net -domain primary -primary_power_net VDD -primary_ground_net VSS
connect_supply_net VDD -ports {VDD}
connect_supply_net VSS -ports {VSS}

create_tracks -layers MET3 -step 22000a -start 11000a
create_tracks -layers MET2 -step 22000a -start 11000a
create_tracks -layers MET1 -step 22000a -start 11000a

report_tracks -type preferred 

create_pg_rails  -xl_area [um2a [expr {$::CORE_LO + 2}]] -yb_area [um2a [expr {$::CORE_LO + 25.5}]] -xr_area [um2a [expr {$::CORE_HI - 2}]] -yt_area [um2a $::CORE_HI] -nets {VDD VSS} -layer MET1 -width 0.14 
create_pg_rings -nets "VDD VSS" -layers "MET1 MET2" -widths 4u -spacing 2.2u  -xl_area [um2a [expr {$::CORE_LO + 6.2}]] -yb_area [um2a [expr {$::CORE_LO + 6.2}]] -xr_area [um2a [expr {$::CORE_HI - 6.2}]] -yt_area [um2a [expr {$::CORE_HI - 6.2}]] -location internal -insert_vias false
insert_pg_vias -report_errors no -xl_area [um2a $::CORE_LO] -yb_area [um2a $::CORE_LO] -xr_area [um2a $::CORE_HI] -yt_area [um2a $::CORE_HI]

#run after pause



# corners: explicit, ring-aligned (91.5 um inset). Needs the 4 PCORNER
# instances in uart_top_ver2_padded.v. create_corner_cells is no longer used
# (it put the corner ~40 um in, 51 um off the pad rings).
apply_corner_constraints
apply_pad_constraints
place_pads
report_pad_ring_gaps

#create_corner_cells -lib_cell PCORNER -x_offset 915000 -y_offset 915000


config_lib_vias -reset curr_selection

config_lib_vias -exact_selection {mincut VIA1}
config_lib_vias -exact_selection {mincut VIA2}

config_lib_vias -exact_selection {regular VIA1 M2_M1}
config_lib_vias -exact_selection {regular VIA2 M3_M2}

config_lib_vias -use_asymmetrical false
config_lib_vias -use_bar false
config_lib_vias -use_4cut false

config_lib_vias -select true


config_route_global -category user_defined
config_route_global -name gr_full_timing_update_thresh -value 0.0

read_constraint /mnt/NewHDD/home/lab_2022104219/CPU/uart_top.sdc

set_input_transition -transition 1 -ports_pins [all_inputs]

# run after pause
run_place_timing -effort high
#write_session -directory db/run_place_timing_session
#if write_session ... is enabled, you can restart from this location by replacing write_session with read_session.

#run after pause
route_global -xl_area [um2a $::CORE_LO] -yb_area [um2a $::CORE_LO] -xr_area [um2a $::CORE_HI] -yt_area [um2a $::CORE_HI]

#write_session -directory db/route_global_session
#run after pause

run_clock_timing 
#write_session -directory db/run_clock_timing_session

# run after pause
run_route_timing -skip_stages dvia
#write_session -directory db/run_route_timing_session
#run after pause
route_final
#write_session -directory db/route_final_session

insert_pad_filler_without_row -partition uart_top_ver2_padded -lib_cells {IOX2 IOX1 IOX3} -orient north

#place this by finding and editing dense area bound to fill the gaps
place_filler_cells -lib_cells {FILLX1 FILLX2 FILLX3 FILLX4} -xl_area [um2a [expr {$::CORE_LO + 2}]] -yb_area [um2a [expr {$::CORE_LO + 25.5}]] -xr_area [um2a [expr {$::CORE_HI - 2}]] -yt_area [um2a $::CORE_HI] -filler_set_prefix false
source /mnt/NewHDD/home/vlsiadmin/TannerEDA/TannerTools_v2021.2/Process/Etri_500nm/pdk_digital/nitro_setup/clean_up_fillers.tcl
prune_floating_fillers 256000

#The lef layout is reconstructed to final gds format to be saved
config_stream_lib  -private {/mnt/NewHDD/home/vlsiadmin/TannerEDA/TannerTools_v2021.2/Process/Etri_500nm/NSPL_0p5um_Digital_CMOS_2P3M_5V_V1p1_12T_PnR/GDS/NSPL_0p5um_Digital_CMOS_2P3M_5V_V1p1_12T_std.gds /mnt/NewHDD/home/lab_2022104219/CPU/GDS/PIC.gds /mnt/NewHDD/home/lab_2022104219/CPU/GDS/PCORNER.gds /mnt/NewHDD/home/lab_2022104219/CPU/GDS/PANA.gds /mnt/NewHDD/home/lab_2022104219/CPU/GDS/POB4.gds /mnt/NewHDD/home/lab_2022104219/CPU/GDS/POB8.gds /mnt/NewHDD/home/lab_2022104219/CPU/GDS/POB24.gds /mnt/NewHDD/home/lab_2022104219/CPU/GDS/PBCT4.gds /mnt/NewHDD/home/lab_2022104219/CPU/GDS/PBCT8.gds /mnt/NewHDD/home/lab_2022104219/CPU/GDS/PVDD.gds /mnt/NewHDD/home/lab_2022104219/CPU/GDS/PVSS.gds /mnt/NewHDD/home/lab_2022104219/CPU/GDS/IOX1.gds /mnt/NewHDD/home/lab_2022104219/CPU/GDS/IOX2.gds /mnt/NewHDD/home/lab_2022104219/CPU/GDS/IOX3.gds}

source /mnt/NewHDD/home/vlsiadmin/TannerEDA/TannerTools_v2021.2/Process/Etri_500nm/pdk_digital/nitro_setup/layermap_converted_to_nitro_commands.tcl

# save gds
config_write_stream -traverse_subpartitions true -unresolved_cells LEF -port_property_number 10
write_stream -file uart_top_ver2_padded.gds -format gds 


#run after pause
#timing delay file to be annotated later on accumulator_8bit_synth_nitro.v 
write_sdf uart_top_ver2.sdf -skip_backslash true

write_verilog -file "uart_top_ver2_synth_nitro.v"






