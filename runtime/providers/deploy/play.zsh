# Deploy provider: Google Play (Gradle bundle, then `fastlane supply` if installed).
# The Gradle build receives -Pjustcode.versionName and -Pjustcode.versionCode.
# The service-account JSON comes from PLAY_JSON_KEY_SECRET via the environment.

_play_gradle() { [[ -x $1/gradlew ]] && print -r -- ./gradlew || print gradle }

deploy_build() {
  local env=$1 version=$2 build=$3 config=$4 src=$5 out=$6 task g
  task=$(df_fill "$GRADLE_TASK_PATTERN" Env "${(C)env}" env "$env" config "$config" Config "${(C)config}")
  g=$(_play_gradle $src)
  local -a cmd=($g $task -Pjustcode.versionName=$version -Pjustcode.versionCode=$build)
  if (( DF_DRY )); then
    df_dry "(cd $src) ${(j: :)${(q-)cmd}}"
    df_dry "copy the newest build/outputs/bundle/**/*.aab to $out/"
    return 0
  fi
  ( cd $src && $cmd ) >>$out/build.log 2>&1 || return 1
  local -a aab=($src/**/build/outputs/bundle/**/*.aab(N.om))
  (( ${#aab} )) || { print -r -- "no .aab found under build/outputs/bundle" >>$out/build.log; return 1 }
  cp $aab[1] $out/
}

deploy_upload() {
  local out=$1
  local -a aab=($out/*.aab(N))
  if (( ! $+commands[fastlane] )); then
    df_fail "play: fastlane is not installed; upload $aab[1] in the Play Console or install fastlane"
    return 1
  fi
  [[ -n $PLAY_PACKAGE ]] || { df_fail "play: PLAY_PACKAGE is not set"; return 1 }
  local -a cmd=(fastlane supply --aab ${aab[1]:-$out/app.aab} --track $PLAY_TRACK --package_name $PLAY_PACKAGE)
  if (( DF_DRY )); then df_dry "${(j: :)${(q-)cmd}} (key from secret $PLAY_JSON_KEY_SECRET)"; return 0; fi
  local key; key=$(df_secret "$PLAY_JSON_KEY_SECRET") || { df_fail "play: secret $PLAY_JSON_KEY_SECRET not found"; return 1 }
  SUPPLY_JSON_KEY_DATA=$key $cmd >>$out/build.log 2>&1
}

deploy_last_build_number() { df_last_uploaded }

deploy_doctor() {
  [[ -x ${BUILD_PROJECT_DIR:-.}/gradlew ]] || (( $+commands[gradle] )) && df_ok "play: gradle found" ||
    { df_fail "play: no ./gradlew and no gradle"; return 1 }
  (( $+commands[fastlane] )) && df_ok "play: fastlane found" || df_skip "play: fastlane not installed (upload will be manual)"
  df_secret_exists "$PLAY_JSON_KEY_SECRET" && df_ok "play: secret $PLAY_JSON_KEY_SECRET present" ||
    { df_fail "play: secret $PLAY_JSON_KEY_SECRET missing; store it with: $(df_secret_store_cmd $PLAY_JSON_KEY_SECRET)"; return 1 }
}
