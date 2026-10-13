# Run only in the separate directory created by prepare_full_cpu_check.ps1.
open_project full_cpu.prj
import_device ef2_4.db -package EF2L45LG144B
elaborate -top design_top_wrapper
optimize_rtl
report_area -file full_cpu_rtl.area
optimize_gate -maparea full_cpu_gate.area
legalize_phy_inst
export_db full_cpu_gate.db
