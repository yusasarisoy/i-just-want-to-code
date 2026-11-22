#!/bin/sh
# leakcheck: fails (exit 1) when any file in the repo looks like it carries
# organisation-specific data. Two checks, every file except images (*.png):
#   1. denylist: one case-insensitive extended regex per line, read from
#      $DEVFLOW_DENYLIST (default ~/.config/devflow-dev/denylist.txt). The file
#      lives outside the repo; hits are reported as file:line and pattern number
#      only, so the patterns themselves are never printed.
#   2. heuristics: unknown hosts/URLs, e-mail addresses not at example.com,
#      digit runs of 5+, non-ASCII letters, and a few sensitivity words.
# Usage: scripts/leakcheck.sh [repo-dir]
set -u
root=$(cd "${1:-$(dirname "$0")/..}" && pwd)
denylist=${DEVFLOW_DENYLIST:-$HOME/.config/devflow-dev/denylist.txt}
if [ ! -r "$denylist" ]; then
  echo "• no denylist at $denylist; running the built-in heuristics only"
  denylist=''
fi
command -v perl >/dev/null 2>&1 || { echo "✗ leakcheck needs perl"; exit 2; }

cd "$root" || exit 2
find . -type f ! -path './.git/*' ! -name '*.png' ! -name '.DS_Store' | sort |
DENYLIST="$denylist" perl -CSD -e '
use strict; use warnings; use utf8;
my @deny; my $pn = 0;
if ($ENV{DENYLIST} ne "") {
  open(my $d, "<:encoding(UTF-8)", $ENV{DENYLIST}) or die "cannot read denylist\n";
  while (my $p = <$d>) {
    chomp $p; $p =~ s/\r$//;
    next if $p =~ /^\s*(#|$)/;
    $pn++;
    my $re = eval { qr/$p/i };
    if ($re) { push @deny, [$pn, $re] } else { print "• denylist pattern #$pn is not a valid regex; skipped\n" }
  }
  print "• denylist has no patterns\n" unless $pn;
}
my $allowed_hosts = qr{^(?:
    (?:[a-z0-9-]+\.)*example(?:\.com|\.org)? | localhost | 127\.0\.0\.1 | host | <host> | id\.atlassian\.com |
    api\.github\.com | github\.com | gitlab\.com | bitbucket\.org | api\.bitbucket\.org |
    (?:api\.)?linear\.app | developers\.linear\.app | api\.tempo\.io | apidocs\.tempo\.io |
    api\.track\.toggl\.com | engineering\.toggl\.com | api\.clockify\.me | docs\.clockify\.me |
    api\.harvestapp\.com | help\.getharvest\.com | <site>\.atlassian\.net |
    developer\.atlassian\.com | support\.atlassian\.com | (?:hooks\.|api\.)?slack\.com |
    (?:[a-z0-9-]+\.)?claude\.(?:ai|com) | (?:[a-z0-9-]+\.)?anthropic\.com |
    docs\.github\.com | docs\.gitlab\.com | developer\.apple\.com | www\.apple\.com |
    developers\.google\.com | developer\.android\.com | firebase\.google\.com |
    learn\.microsoft\.com | adaptivecards\.io | docs\.fastlane\.tools |
    developers\.cloudflare\.com | tailscale\.com | www\.wireguard\.com | openvpn\.net |
    docs\.paloaltonetworks\.com | help\.zscaler\.com | www\.cisco\.com | docs\.fortinet\.com |
    direnv\.net | jqlang\.org | curl\.se | www\.zsh\.org | docs\.python\.org
  )$}xi;
my $tld = qr/(?:com|net|org|io|dev|app|co|tr|de|uk|eu|cloud|local|corp|lan|tools|se|ai|me|us|info|biz)/i;
my $words = qr/\b(?:in[t]ernal|confi[d]ential|propri[e]tary)\b/i;
my $hits = 0;
sub hit { my ($f, $n, $what) = @_; print "$f:$n: $what\n"; $hits++; }
while (my $file = <STDIN>) {
  chomp $file; $file =~ s{^\./}{};
  open(my $fh, "<:encoding(UTF-8)", $file) or next;
  my $n = 0;
  while (my $line = <$fh>) {
    $n++;
    for my $d (@deny) { hit($file, $n, "denylist pattern #$d->[0]") if $line =~ $d->[1]; }
    while ($line =~ m{\b(?:https?|ssh|git)://(?:[^\s/@"<>]+@)?([A-Za-z0-9<>.-]+)(?::\d+)?([^\s"\x27<>)\]]*)}g) {
      my ($h, $p) = ($1, $2);
      if ($h !~ $allowed_hosts) { hit($file, $n, "url host: $h"); next; }
      hit($file, $n, "github.com url outside the plugin repo: $h$p")
        if $h =~ /^github\.com$/i && $p ne "" && $p !~ m{^/(?:yusasarisoy(?:/i-just-want-to-code)?|alice/[\w.-]+|bob/[\w.-]+)(?:[/.#]|$)}i;
    }
    while ($line =~ /(?<![\w.\/~-])((?:[a-z0-9-]+\.)+$tld)(?![\w-])/gi) {
      my $h = $1;
      next if $h =~ /^justcode\.local$/i;
      hit($file, $n, "hostname: $h") if $h !~ $allowed_hosts;
    }
    while ($line =~ /([A-Za-z0-9._%+-]+)@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+)/g) {
      my ($u, $d) = ($1, $2);
      next if $u eq "git" || $d =~ /^(?:[a-z0-9-]+\.)*example\.com$/i;
      hit($file, $n, "e-mail address: $u\@$d");
    }
    while ($line =~ /(?<![0-9])([0-9]{5,})(?![0-9])/g) {
      my $r = $1;
      next if $r =~ /^(\d)\1+$/ || "1234567890" =~ /\Q$r\E/;
      hit($file, $n, "digit run: $r");
    }
    hit($file, $n, "non-ASCII letter") if $line =~ /(?=\P{ASCII})\p{L}/;
    if ($line =~ $words) {
      my $w = $&;
      hit($file, $n, "word: $w") unless $w =~ /^in/i && $line =~ /PLAY_TRACK|\btracks?\b/i;
    }
  }
}
if ($hits) { print "✗ leakcheck: $hits finding(s)\n"; exit 1 }
print "✓ leakcheck: clean" . (@deny ? " (heuristics + " . scalar(@deny) . " denylist pattern(s))" : " (heuristics only)") . "\n";
exit 0;
'
