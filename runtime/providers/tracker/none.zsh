# Tracker provider: none. Nothing is read or written; no secret is touched.
tracker_get() { DF_TICKET_STATUS='' DF_TICKET_ID=''; df_unsupported "ticket lookup" none }
tracker_move() { df_unsupported "status change" none }
tracker_url() { return 3 }
tracker_find_by_title() { df_unsupported "ticket search" none }
tracker_create() { df_unsupported "ticket creation" none }
tracker_set_estimate() { df_unsupported estimates none }
tracker_doctor() { df_skip "tracker: none configured"; return 0 }
