# Time provider: none. Nothing is read or written; no secret is touched.
time_list() { df_unsupported "time tracking" none }
time_create() { df_unsupported "time tracking" none }
time_update() { df_unsupported "time tracking" none }
time_day_total() { df_unsupported "time tracking" none }
time_week_totals() { df_unsupported "time tracking" none }
time_doctor() { df_skip "time: none configured"; return 0 }
