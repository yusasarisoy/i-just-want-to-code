# Deploy provider: TestFlight (xcodebuild archive, then -exportArchive with
# destination "upload"). Signing uses Xcode's accounts unless ASC_KEY_ID,
# ASC_ISSUER_ID and ASC_KEY_PATH (an App Store Connect API key file) are set.

_tf_run() {  # _tf_run <dir> <log> <cmd...>
  local dir=$1 log=$2; shift 2
  if (( DF_DRY )); then df_dry "(cd $dir) ${(j: :)${(q-)@}}"; return 0; fi
  ( cd $dir && "$@" ) >>$log 2>&1
}

# deploy_build <env> <version> <build> <config> <srcdir> <outdir>
deploy_build() {
  local env=$1 version=$2 build=$3 config=$4 src=$5 out=$6 scheme
  local -a proj
  scheme=$(df_fill "$XCODE_SCHEME_PATTERN" app "$APP_NAME" env "$env" config "$config")
  if [[ -n $XCODE_WORKSPACE ]]; then proj=(-workspace $XCODE_WORKSPACE)
  elif [[ -n $XCODE_PROJECT ]]; then proj=(-project $XCODE_PROJECT)
  else df_fail "testflight: set XCODE_WORKSPACE or XCODE_PROJECT"; return 1
  fi
  _tf_run $src $out/build.log xcodebuild $proj -scheme "$scheme" -configuration "$config" \
    -destination 'generic/platform=iOS' -archivePath $out/${APP_NAME:-App}.xcarchive \
    MARKETING_VERSION=$version CURRENT_PROJECT_VERSION=$build archive
}

deploy_upload() {
  local out=$1
  local -a auth=(-allowProvisioningUpdates)
  [[ -n $ASC_KEY_ID && -n $ASC_ISSUER_ID && -n $ASC_KEY_PATH ]] &&
    auth+=(-authenticationKeyPath ${ASC_KEY_PATH/#\~/$HOME} -authenticationKeyID $ASC_KEY_ID -authenticationKeyIssuerID $ASC_ISSUER_ID)
  if (( ! DF_DRY )); then
    print -r -- '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>upload</string>
</dict></plist>' >$out/ExportOptions.plist
  fi
  _tf_run $out $out/build.log xcodebuild -exportArchive -archivePath $out/${APP_NAME:-App}.xcarchive \
    -exportOptionsPlist $out/ExportOptions.plist -exportPath $out/export $auth
}

deploy_last_build_number() { df_last_uploaded }

deploy_doctor() {
  (( $+commands[xcodebuild] )) && df_ok "testflight: xcodebuild found" || { df_fail "testflight: xcodebuild not found (install Xcode)"; return 1 }
  [[ -n $XCODE_WORKSPACE || -n $XCODE_PROJECT ]] || { df_fail "testflight: set XCODE_WORKSPACE or XCODE_PROJECT"; return 1 }
  [[ -n $APP_NAME ]] || { df_fail "testflight: APP_NAME is not set"; return 1 }
}
