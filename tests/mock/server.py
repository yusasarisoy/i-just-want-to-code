#!/usr/bin/env python3
"""One fake server for every provider API justcode talks to.

The first path segment picks the provider:
  /github /gitlab/api/v4 /bitbucket/2.0 /jira-cloud /jira-dc /linear/graphql
  /tempo/4 /toggl/api/v9 /clockify/api/v1 /hooks/<name> /preview
Response shapes follow each vendor's public API documentation (trimmed).

Every request is logged as "METHOD path body" (one line) to --log.
Failure switches, comma separated, from the MOCK_FAIL env, the file named by
MOCK_FAIL_FILE (re-read on every request) or an X-Mock-Fail header:
  401 | 500 | timeout            every request
  401@sub | 500@sub | timeout@sub only paths containing "sub"
  exists        searches find an issue with the searched title; PR lookups find one
  merge-now     pull/merge requests report that they can merge immediately
  search-fails  ticket searches answer 500
  draft         existing pull requests are drafts
  state-unknown GitHub pull requests report mergeable_state "unknown" (just created)
  preparing-briefly GitLab merge requests are "preparing" with no pipeline for 1 s after the first read
  logged-10     Tempo also lists a 1h ABC-123 worklog at 10:00 (what a first "ship -l 1h" wrote)
"""
import argparse
import json
import os
import re
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qs, unquote

ARGS = None
LOCK = threading.Lock()
SEEN = {}  # first-seen times, for switches whose answer changes over time
USER = os.environ.get("MOCK_USER", "alice")
HOST = "https://git.example.com"


def switches(handler):
    items = []
    items += os.environ.get("MOCK_FAIL", "").split(",")
    path = os.environ.get("MOCK_FAIL_FILE")
    if path and os.path.exists(path):
        with open(path) as f:
            items += f.read().replace("\n", ",").split(",")
    items += (handler.headers.get("X-Mock-Fail") or "").split(",")
    return {s.strip() for s in items if s.strip()}


def pull(number=7, draft=False, merge_now=False, reviewers=None):
    return {
        "number": number, "node_id": f"PR_node{number}", "html_url": f"{HOST}/alice/myapp/pull/{number}",
        "title": "Add login screen", "draft": draft, "body": "",
        "requested_reviewers": [{"login": r} for r in (reviewers or [])],
        "mergeable_state": "clean" if merge_now else "blocked",
    }


def mr(iid=7, draft=False, merge_now=False):
    return {
        "iid": iid, "web_url": f"{HOST}/alice/myapp/-/merge_requests/{iid}",
        "title": ("Draft: " if draft else "") + "Add login screen", "draft": draft, "description": "",
        "reviewers": [], "head_pipeline": {"id": 11},
        "detailed_merge_status": "mergeable" if merge_now else "ci_still_running",
    }


def bb_pr(pid=7, draft=False):
    return {"id": pid, "title": "Add login screen", "draft": draft, "description": "", "reviewers": [],
            "links": {"html": {"href": f"https://bitbucket.org/alice/myapp/pull-requests/{pid}"}}}


JIRA_FIELDS = [
    {"fieldId": "summary", "name": "Summary", "schema": {"type": "string"}},
    {"fieldId": "description", "name": "Description", "schema": {"type": "string"}},
    {"fieldId": "priority", "name": "Priority", "schema": {"type": "priority"},
     "allowedValues": [{"id": "1", "name": "High"}, {"id": "2", "name": "Medium"}, {"id": "3", "name": "Low"}]},
    {"fieldId": "components", "name": "Components", "schema": {"type": "array", "items": "component"},
     "allowedValues": [{"id": "10", "name": "Mobile"}, {"id": "11", "name": "Backend"}]},
    {"fieldId": "fixVersions", "name": "Fix versions", "schema": {"type": "array", "items": "version"},
     "allowedValues": [{"id": "20", "name": "1.2.3"}]},
    {"fieldId": "environment", "name": "Severity", "schema": {"type": "string"}},
    {"fieldId": "customfield_101", "name": "Severity", "schema": {"type": "option", "custom": "select"},
     "allowedValues": [{"id": "31", "value": "Minor"}, {"id": "32", "value": "Major"}]},
    {"fieldId": "customfield_102", "name": "Sprint", "schema": {"type": "array", "custom": "com.pyxis.greenhopper.jira:gh-sprint"}},
    {"fieldId": "customfield_103", "name": "Story Points", "schema": {"type": "number"}},
    {"fieldId": "customfield_104", "name": "Epic Link", "schema": {"type": "any"}},
]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def reply(self, code=200, body=None):
        data = b"" if body is None else (body if isinstance(body, bytes) else json.dumps(body).encode())
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def handle_any(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length).decode() if length else ""
        with LOCK, open(ARGS.log, "a") as f:
            f.write(f"{self.command} {self.path} {' '.join(raw.split())}\n")
        sw = switches(self)
        for s in sw:
            code, _, sub = s.partition("@")
            if sub and sub not in self.path:
                continue
            if code in ("401", "500"):
                return self.reply(int(code), {"message": f"mock {code}"})
            if code == "timeout":
                time.sleep(float(os.environ.get("MOCK_TIMEOUT_SECS", "25")))
                return self.reply(504, {"message": "mock timeout"})
        try:
            body = json.loads(raw) if raw else {}
        except ValueError:
            body = {}
        u = urlsplit(self.path)
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        parts = u.path.strip("/").split("/")
        route = getattr(self, "r_" + parts[0].replace("-", "_"), None)
        if route is None:
            return self.reply(404, {"message": "no such mock route"})
        result = route(self.command, "/" + "/".join(parts[1:]), q, body, sw)
        if result is None:
            return self.reply(404, {"message": f"mock: no route for {self.command} {u.path}"})
        code, payload = result if isinstance(result, tuple) else (200, result)
        return self.reply(code, payload)

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = handle_any

    # ------------------------------------------------------------ code hosts
    def r_github(self, m, p, q, b, sw):
        if p == "/user":
            return {"login": USER}
        if p == "/graphql":
            if "enablePullRequestAutoMerge" in b.get("query", "") and "merge-now" in sw:
                return {"data": None, "errors": [{"message": "Pull request is in clean status"}]}
            return {"data": {"ok": {"clientMutationId": None}}}
        mo = re.match(r"^/repos/[^/]+/[^/]+(/.*)?$", p)
        if not mo:
            return None
        rest = mo.group(1) or ""
        if rest == "":
            return {"full_name": "alice/myapp"}
        if rest == "/pulls" and m == "GET":
            return [pull(draft="draft" in sw)] if "exists" in sw or "pr-exists" in sw else []
        if rest == "/pulls" and m == "POST":
            return 201, pull(draft=bool(b.get("draft")))
        if re.match(r"^/pulls/\d+$", rest):
            pr = pull(merge_now="merge-now" in sw, draft="draft" in sw)
            if "state-unknown" in sw:
                pr["mergeable_state"] = "unknown"
            return pr
        if rest.endswith("/requested_reviewers"):
            return 201, pull(reviewers=b.get("reviewers"))
        if rest.endswith("/labels"):
            return [{"name": n} for n in b.get("labels", [])]
        return None

    def r_gitlab(self, m, p, q, b, sw):
        p = p.removeprefix("/api/v4")
        if p == "/user":
            return {"username": USER}
        if p == "/users":
            return [{"id": 2, "username": q.get("username")}]
        mo = re.match(r"^/projects/[^/]+(/.*)?$", p)
        if not mo:
            return None
        rest = mo.group(1) or ""
        if rest == "":
            return {"path_with_namespace": "alice/myapp"}
        if rest == "/merge_requests" and m == "GET":
            return [mr(draft="draft" in sw)] if "exists" in sw or "pr-exists" in sw else []
        if rest == "/merge_requests" and m == "POST":
            return 201, mr(draft=b.get("title", "").startswith("Draft:"))
        if re.match(r"^/merge_requests/\d+(/merge)?$", rest):
            out = mr(merge_now="merge-now" in sw, draft="draft" in sw)
            if "preparing-briefly" in sw and m == "GET":
                with LOCK:
                    since = SEEN.setdefault("preparing-briefly", time.monotonic())
                if time.monotonic() - since < 1:
                    out.update({"detailed_merge_status": "preparing", "head_pipeline": None})
            return out
        if rest == "/pipelines":
            return [{"id": 11, "sha": q.get("sha"), "status": "skipped"}]
        if rest.startswith("/pipelines/11/jobs"):
            return [{"id": 21, "name": "nudge", "status": "manual"}]
        if re.match(r"^/jobs/21/(play|cancel)$", rest):
            return {"id": 21}
        return None

    def r_bitbucket(self, m, p, q, b, sw):
        p = p.removeprefix("/2.0")
        if p == "/user":
            return {"username": USER, "account_id": "acc-alice"}
        mo = re.match(r"^/repositories/[^/]+/[^/]+(/.*)?$", p)
        if not mo:
            return None
        rest = mo.group(1) or ""
        if rest == "":
            return {"full_name": "alice/myapp"}
        if rest == "/pullrequests" and m == "GET":
            return {"values": [bb_pr(draft="draft" in sw)] if "exists" in sw or "pr-exists" in sw else []}
        if rest == "/pullrequests" and m == "POST":
            return 201, bb_pr(draft=bool(b.get("draft")))
        if re.match(r"^/pullrequests/\d+$", rest):
            return bb_pr(draft="draft" in sw)
        return None

    # ------------------------------------------------------------ trackers
    def jira(self, m, p, q, b, sw, kind):
        if p.startswith("/rest/tempo-timesheets/4"):
            return self.tempo_dc(m, p.removeprefix("/rest/tempo-timesheets/4"), q, b, sw)
        mo = re.match(r"^/rest/api/(\d)(/.*)$", p)
        if mo:
            rest = mo.group(2)
            if rest == "/myself":
                return {"emailAddress": f"{USER}@example.com", "name": USER, "accountId": "acc-alice"}
            if rest.startswith("/project/"):
                return {"key": rest.split("/")[2]}
            if rest in ("/search/jql", "/search"):
                if "search-fails" in sw:
                    return 500, {"errorMessages": ["search is down"]}
                if "exists" in sw:
                    phrase = re.search(r'summary ~ "([^"]*)"', unquote(q.get("jql", "")))
                    title = " ".join((phrase.group(1) if phrase else "").split())
                    return {"issues": [{"key": "ABC-7", "fields": {"summary": title}}]}
                return {"issues": []}
            if rest == "/user/search":
                return [{"accountId": "acc-bob"}]
            if rest.startswith("/issue/createmeta/"):
                seg = rest.split("/")
                if len(seg) == 5:
                    types = [{"id": "1", "name": "Bug"}, {"id": "2", "name": "Story"}, {"id": "3", "name": "Task"}]
                    return {"issueTypes": types, "values": types}
                return {"fields": JIRA_FIELDS, "values": JIRA_FIELDS}
            if rest == "/issue" and m == "POST":
                return 201, {"id": "200", "key": "ABC-200"}
            im = re.match(r"^/issue/([^/]+)(/transitions)?$", rest)
            if im:
                key = im.group(1)
                if im.group(2):
                    if m == "POST":
                        return 204, None
                    return {"transitions": [{"id": "31", "name": "Review", "to": {"name": "In Review"}},
                                            {"id": "41", "name": "Done", "to": {"name": "Done"}}]}
                if key.isdigit():
                    key = "ABC-123"
                return {"id": "101", "key": key, "fields": {"status": {"name": "In Progress"}, "summary": "Login"}}
            return None
        if p.startswith("/rest/agile/1.0/board/"):
            return {"values": [{"id": 9, "name": "Sprint 9", "state": "active"}]}
        if re.match(r"^/rest/agile/1.0/issue/[^/]+/estimation$", p):
            return {"fieldId": "customfield_103", "value": b.get("value")}
        return None

    def r_jira_cloud(self, *a):
        return self.jira(*a, "cloud")

    def r_jira_dc(self, *a):
        return self.jira(*a, "dc")

    def r_linear(self, m, p, q, b, sw):
        query = b.get("query", "")
        v = b.get("variables", {})
        if query.lstrip().startswith("mutation"):
            if "issueCreate" in query:
                return {"data": {"issueCreate": {"success": True, "issue": {"identifier": "ENG-100"}}}}
            return {"data": {"issueUpdate": {"success": True}}}
        if "viewer" in query:
            return {"data": {"viewer": {"email": f"{USER}@example.com"}}}
        if "teams" in query:
            return {"data": {"teams": {"nodes": [{"id": "team-1", "labels": {"nodes": [{"id": "lab-1", "name": "Bug"}]}}]}}}
        if "issues(" in query:
            if "search-fails" in sw:
                return 500, {"errors": [{"message": "search is down"}]}
            nodes = [{"identifier": "ENG-7"}] if "exists" in sw else []
            return {"data": {"issues": {"nodes": nodes}}}
        if "issue(" in query:
            ident = v.get("id", "ENG-42")
            return {"data": {"issue": {"id": "lin-1", "identifier": ident, "url": f"https://linear.app/example/issue/{ident}",
                                       "state": {"name": "In Progress"},
                                       "team": {"states": {"nodes": [{"id": "st-1", "name": "In Progress"},
                                                                     {"id": "st-2", "name": "In Review"},
                                                                     {"id": "st-3", "name": "Done"}]}}}}}
        return None

    # ------------------------------------------------------------ time trackers
    def r_tempo(self, m, p, q, b, sw):
        p = p.removeprefix("/4")
        if p.startswith("/worklogs/user/"):
            day = q.get("from", "2026-01-05")
            rows = [{"tempoWorklogId": 1, "issue": {"id": 101}, "startDate": day, "startTime": "09:00:00",
                     "timeSpentSeconds": 3600, "description": "Development", "attributes": {"values": []}}]
            if "logged-10" in sw:
                rows.append({**rows[0], "tempoWorklogId": 2, "startTime": "10:00:00"})
            return {"results": rows}
        if p == "/worklogs" and m == "POST":
            return 200, {"tempoWorklogId": 2}
        if re.match(r"^/worklogs/\d+$", p):
            return {"tempoWorklogId": int(p.split("/")[-1])}
        return None

    def tempo_dc(self, m, p, q, b, sw):
        if p == "/worklogs/search":
            day = b.get("from", "2026-01-05")
            return [{"tempoWorklogId": 1, "issue": {"key": "ABC-123", "id": 101}, "started": f"{day} 09:00:00.000",
                     "timeSpentSeconds": 3600, "comment": "Development", "attributes": {}}]
        if p == "/worklogs" and m == "POST":
            return [{"tempoWorklogId": 2}]
        if re.match(r"^/worklogs/\d+$", p):
            return {"tempoWorklogId": int(p.split("/")[-1])}
        return None

    def r_toggl(self, m, p, q, b, sw):
        p = p.removeprefix("/api/v9")
        if p == "/me":
            return {"email": f"{USER}@example.com"}
        if p == "/me/time_entries":
            day = q.get("start_date", "2026-01-05T00:00:00Z")[:10]
            return [{"id": 1, "workspace_id": 1, "start": f"{day}T08:00:00+00:00", "duration": 3600,
                     "description": "ENG-42 Development", "tags": []},
                    {"id": 3, "workspace_id": 1, "start": f"{day}T12:00:00+00:00", "duration": -1,
                     "description": "running", "tags": []}]
        if re.match(r"^/workspaces/\d+/time_entries(/\d+)?$", p):
            return {"id": 2}
        return None

    def r_clockify(self, m, p, q, b, sw):
        p = p.removeprefix("/api/v1")
        if p == "/user":
            return {"id": "user-1", "email": f"{USER}@example.com"}
        if re.match(r"^/workspaces/[^/]+/user/[^/]+/time-entries$", p):
            day = q.get("start", "2026-01-05T00:00:00Z")[:10]
            return [{"id": "e1", "description": "ENG-42 Development", "tagIds": [],
                     "timeInterval": {"start": f"{day}T08:00:00Z", "end": f"{day}T09:00:00Z"}}]
        if re.match(r"^/workspaces/[^/]+/time-entries(/[^/]+)?$", p):
            return {"id": "e2"}
        return None

    # ------------------------------------------------------------ messages and custom commands
    def r_hooks(self, m, p, q, b, sw):
        return (200, b"ok") if m == "POST" else None

    def r_preview(self, m, p, q, b, sw):
        if p == "/status":
            return {"ok": True}
        if p == "/deploy" and m == "POST":
            return 201, {"url": "https://preview.example.com/7"}
        return None


def main():
    global ARGS
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=0)
    ap.add_argument("--port-file")
    ap.add_argument("--log", required=True)
    ARGS = ap.parse_args()
    srv = ThreadingHTTPServer(("127.0.0.1", ARGS.port), Handler)
    if ARGS.port_file:
        tmp = ARGS.port_file + ".tmp"
        with open(tmp, "w") as f:
            f.write(str(srv.server_address[1]))
        os.replace(tmp, ARGS.port_file)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    sys.exit(main())
