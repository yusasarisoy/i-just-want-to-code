# Deploy provider: none.
deploy_build() { df_unsupported builds none }
deploy_upload() { df_unsupported uploads none }
deploy_last_build_number() { df_last_uploaded }
deploy_doctor() { df_skip "deploy: none configured"; return 0 }
