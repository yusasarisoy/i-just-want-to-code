# Deploy provider: command. Runs DEPLOY_COMMAND with zsh -c in the build tree,
# with JUSTCODE_ENV, JUSTCODE_VERSION, JUSTCODE_BUILD, JUSTCODE_CONFIG, JUSTCODE_SRC
# and JUSTCODE_OUT exported. The command builds and uploads in one go.

deploy_build() {
  [[ -n $DEPLOY_COMMAND ]] || { df_fail "command: DEPLOY_COMMAND is not set"; return 1 }
  if (( DF_DRY )); then df_dry "(cd $5) JUSTCODE_ENV=$1 JUSTCODE_VERSION=$2 JUSTCODE_BUILD=$3 zsh -c ${(q-)DEPLOY_COMMAND}"; return 0; fi
  ( cd $5 && JUSTCODE_ENV=$1 JUSTCODE_VERSION=$2 JUSTCODE_BUILD=$3 JUSTCODE_CONFIG=$4 JUSTCODE_SRC=$5 JUSTCODE_OUT=$6 \
      zsh -c "$DEPLOY_COMMAND" ) >>$6/build.log 2>&1
}

deploy_upload() { df_skip "upload is part of DEPLOY_COMMAND"; return 0 }
deploy_last_build_number() { df_last_uploaded }
deploy_doctor() { [[ -n $DEPLOY_COMMAND ]] && df_ok "command: DEPLOY_COMMAND set" || { df_fail "command: DEPLOY_COMMAND is not set"; return 1 } }
