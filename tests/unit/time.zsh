#!/usr/bin/env zsh
# Pure time helpers: ranges, durations, days, week bounds, formatting, overlap.
HERE=${0:A:h}
source $HERE/../lib/assert.zsh 2>/dev/null || source $HERE/assert.zsh
DF_ROOT=${JUSTCODE_ROOT:-$HERE/../../runtime}
export HOME=$(mktemp -d "${TMPDIR:-/tmp}/justcode-unit.XXXXXX"); cd $HOME
source $DF_ROOT/lib/justcode-lib.zsh

print "time parsing"
t_eq "range 9-10" "$(df_parse_range 9-10)" "540 600"
t_eq "range 09:30-12:00" "$(df_parse_range 09:30-12:00)" "570 720"
t_no "range 23-1 rejected (end before start)" df_parse_range 23-1
t_no "range 10-10 rejected" df_parse_range 10-10
t_no "range 25-26 rejected" df_parse_range 25-26
t_no "range without dash rejected" df_parse_range 9
t_eq "duration 1h30m" "$(df_parse_duration 1h30m)" 5400
t_eq "duration 45m" "$(df_parse_duration 45m)" 2700
t_eq "duration 2h" "$(df_parse_duration 2h)" 7200
t_no "duration 0m rejected" df_parse_duration 0m
t_no "duration empty rejected" df_parse_duration ''
t_no "duration 1x rejected" df_parse_duration 1x

print "days"
t_eq "13.10.2026 -> 2026-10-13" "$(df_parse_day 13.10.2026)" 2026-10-13
t_eq "1.2.2026 -> 2026-02-01" "$(df_parse_day 1.2.2026)" 2026-02-01
t_eq "ISO day kept" "$(df_parse_day 2026-03-04)" 2026-03-04
t_no "31.02.2026 rejected" df_parse_day 31.02.2026
t_no "garbage day rejected" df_parse_day someday
JUSTCODE_NOW=$(strftime -r '%Y-%m-%d %H:%M' '2026-03-02 10:00')
t_eq "today uses JUSTCODE_NOW" "$(df_parse_day today)" 2026-03-02
t_eq "yesterday across a month" "$(df_parse_day yesterday)" 2026-03-01

print "week bounds"
JUSTCODE_NOW=$(strftime -r '%Y-%m-%d %H:%M' '2026-01-01 10:00')
t_eq "week around a year boundary" "$(df_week_bounds 0)" "2025-12-29 2026-01-04"
t_eq "one week back across a year" "$(df_week_bounds 1)" "2025-12-22 2025-12-28"
JUSTCODE_NOW=$(strftime -r '%Y-%m-%d %H:%M' '2026-10-01 23:30')
t_eq "week around a month boundary" "$(df_week_bounds 0)" "2026-09-28 2026-10-04"
JUSTCODE_NOW=$(strftime -r '%Y-%m-%d %H:%M' '2026-10-04 08:00')
t_eq "Sunday belongs to the same week" "$(df_week_bounds 0)" "2026-09-28 2026-10-04"
unset JUSTCODE_NOW

print "formatting"
t_eq "fmt 5400" "$(df_fmt_duration 5400)" 1h30m
t_eq "fmt 7200" "$(df_fmt_duration 7200)" 2h
t_eq "fmt 2700" "$(df_fmt_duration 2700)" 45m
t_eq "fmt 0" "$(df_fmt_duration 0)" 0m
t_eq "min to HH:MM" "$(df_min_to_hhmm 570)" 09:30

print "overlap"
t_ok "9-10 overlaps 9:30-11" df_overlaps 540 600 570 660
t_no "9-10 touches 10-11 without overlap" df_overlaps 540 600 600 660
t_ok "inner range overlaps" df_overlaps 540 720 600 630
t_no "disjoint ranges" df_overlaps 540 600 700 760

rm -rf $HOME
t_done
