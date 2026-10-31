"""Tests for bin/agentctl.

Unit tests cover argv rewriting and env handling. Integration tests run a private
tmux server (-L socket) with fake `claude`, `copilot` and service binaries that
register sessions exactly like the real tools, then kill the server and restore.
The real tmux server and real agent state are never touched: HOME, the tmux
socket, the agentctl state dir and the Claude/Copilot dirs all live in tmp_path.

    python3 -m pytest tests/test_agentctl.py -q
"""
from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import sys
import textwrap
import time
import uuid
import importlib.util
from importlib.machinery import SourceFileLoader
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
AGENTCTL = REPO / "bin/agentctl"
TMUX = shutil.which("tmux")


def _load_module(name: str):
    spec = importlib.util.spec_from_loader(name, SourceFileLoader(name, str(AGENTCTL)))
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod          # dataclasses resolve annotations through sys.modules
    spec.loader.exec_module(mod)
    return mod


def load(env: dict[str, str]):
    old = {k: os.environ.get(k) for k in env}
    os.environ.update(env)
    try:
        return _load_module(f"agentctl_{uuid.uuid4().hex}")
    finally:
        for k, v in old.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


# ----------------------------------------------------------------------------- unit

@pytest.fixture(scope="module")
def ac(tmp_path_factory):
    d = tmp_path_factory.mktemp("unit")
    return load({"AGENTCTL_STATE": str(d / "state"), "HOME": str(d)})


SID = "1eed150a-8209-4800-ac1a-20264f264c48"


@pytest.mark.parametrize("argv,expect", [
    (["claude", "--dangerously-skip-permissions", "--model", "claude-opus-5.5[1m]", "--continue"],
     ["claude", "--dangerously-skip-permissions", "--model", "claude-opus-5.5[1m]", "--resume", SID]),
    (["claude", "--resume", "e5ac32a0-3815-42fa-a25f-8ddd25c9b2d4", "--model", "x"],
     ["claude", "--model", "x", "--resume", SID]),
    (["claude", "-r", "--model", "x"], ["claude", "--model", "x", "--resume", SID]),
    (["claude", "--resume=abc", "-c"], ["claude", "--resume", SID]),
    (["claude", "--add-dir", "/a", "/b", "--verbose", "fix the bug"],
     ["claude", "--add-dir", "/a", "/b", "--verbose", "--resume", SID]),
    (["claude", "--fork-session", "--session-id", "u", "-n", "nm", "-w", "--tmux"], ["claude", "--resume", SID]),
    (["claude", "--setting-sources", "user,project,local", "--dangerously-skip-permissions"],
     ["claude", "--setting-sources", "user,project,local", "--dangerously-skip-permissions", "--resume", SID]),
])
def test_claude_resume_argv(ac, argv, expect):
    assert ac.resume_argv(dict(kind="claude", argv=argv, session_id=SID)) == expect


@pytest.mark.parametrize("argv,expect", [
    (["copilot", "--yolo", "--resume", "f6cafc1b-7509-40e9-908c-bc16f8211528"], ["copilot", "--yolo", "--resume", SID]),
    (["copilot", "--yolo", "--resume=abc", "--allow-all-tools"], ["copilot", "--yolo", "--allow-all-tools", "--resume", SID]),
    (["copilot", "--continue", "--model", "gpt-5", "--allow-tool", "shell"], ["copilot", "--model", "gpt-5", "--allow-tool", "shell", "--resume", SID]),
    (["copilot", "-i", "start here", "--yolo"], ["copilot", "--yolo", "--resume", SID]),
    (["copilot", "-C", "/w", "--yolo"], ["copilot", "-C", "/w", "--yolo", "--resume", SID]),
    (["copilot", "--allow-tool", "shell", "write", "--yolo"], ["copilot", "--allow-tool", "shell", "write", "--yolo", "--resume", SID]),
    (["copilot", "--allow-tool", "--yolo"], ["copilot", "--allow-tool", "--yolo", "--resume", SID]),
])
def test_copilot_resume_argv(ac, argv, expect):
    assert ac.resume_argv(dict(kind="copilot", argv=argv, session_id=SID)) == expect


def test_settled_idle_requires_age(ac, monkeypatch):
    monkeypatch.setattr(ac, "pane_busy", lambda pid: False)
    up = float(open("/proc/uptime").read().split()[0])
    monkeypatch.setattr(ac, "proc_stat", lambda pid: ("zsh", 1, pid, int((up - 5) * ac.CLK_TCK)))
    assert not ac.settled_idle(1234)
    monkeypatch.setattr(ac, "proc_stat", lambda pid: ("zsh", 1, pid, int((up - 120) * ac.CLK_TCK)))
    assert ac.settled_idle(1234)


def test_resume_without_id_has_no_guess(ac):
    assert ac.resume_argv(dict(kind="claude", argv=["claude", "--continue"], session_id=None)) == ["claude"]


def test_resume_uses_recorded_exe_only_if_present(ac, tmp_path):
    exe = tmp_path / "claude"
    exe.write_text("#!/bin/sh\n")
    exe.chmod(0o755)
    a = dict(kind="claude", argv=["claude"], session_id=SID, exe=str(exe))
    assert ac.resume_argv(a)[0] == str(exe)
    a["exe"] = str(tmp_path / "gone")
    assert ac.resume_argv(a)[0] == "claude"


@pytest.mark.parametrize("argv,kind", [
    (["claude"], "claude"), (["claude", "-p", "hi"], None), (["claude", "--print"], None),
    (["/x/claude.exe", "--continue"], "claude"), (["copilot", "--yolo"], "copilot"),
    (["copilot", "-p", "x"], None), (["copilot", "--prompt=x"], None), (["copilot", "--acp"], None),
    (["python3", "/x/claude", "--continue"], "claude"), (["node", "/x/copilot"], "copilot"),
    (["python3", "-m", "claude"], None), (["vim", "claude"], None), ([], None),
])
def test_agent_kind(ac, argv, kind):
    assert ac.agent_kind(argv) == kind


def test_pane_command_quotes_and_env(ac, monkeypatch):
    monkeypatch.setenv("AGENTCTL_PANE_SHELL", "/bin/bash")
    cmd = ac.pane_command(["claude", "--model", "a b[1m]", "--resume", SID],
                          {"ANTHROPIC_BASE_URL": "http://127.0.0.1:4141", "X": "it's"}, ["HTTPS_PROXY"])
    out = subprocess.run(["bash", "-c", cmd.replace("exec /bin/bash -lic", "printf '%s' ")],
                         capture_output=True, text=True).stdout
    inner = out
    assert inner.startswith("env -u HTTPS_PROXY ANTHROPIC_BASE_URL=http://127.0.0.1:4141 'X=it'\"'\"'s' claude")
    assert "'a b[1m]'" in inner and inner.endswith("; exec /bin/bash -l")


def test_env_overlay_keeps_launcher_env_drops_secrets(ac, monkeypatch):
    shell = {"PATH": "/bin", "ANTHROPIC_MODEL": "same", "HTTPS_PROXY": "http://p"}
    agent = {"PATH": "/bin", "ANTHROPIC_MODEL": "same", "ANTHROPIC_BASE_URL": "http://127.0.0.1:4141",
             "ANTHROPIC_AUTH_TOKEN": "s3cr3t", "COPILOT_LOADER_PID": "1", "GH_CONFIG_DIR": "/g"}
    monkeypatch.setattr(ac, "environ", lambda pid: agent if pid == 2 else shell)
    keep, unset = ac.env_overlay(2, 1)
    assert keep == {"ANTHROPIC_BASE_URL": "http://127.0.0.1:4141", "GH_CONFIG_DIR": "/g"}
    assert unset == ["HTTPS_PROXY"]


# ----------------------------------------------------------------------------- integration

FAKE_CLAUDE = r'''#!/usr/bin/env python3
"""Fake claude: registers ~/.claude/sessions/<pid>.json like Claude Code, then idles."""
import json, os, sys, time, uuid
args = sys.argv[1:]
if "-p" in args or "--print" in args:
    sys.exit(0)
sid = None
for i, a in enumerate(args):
    if a in ("--resume", "-r") and i + 1 < len(args):
        sid = args[i + 1]
sid = sid or str(uuid.uuid4())
home = os.path.expanduser("~/.claude")
os.makedirs(f"{home}/sessions", exist_ok=True)
with open(f"/proc/{os.getpid()}/stat") as f:
    start = f.read().rsplit(")", 1)[1].split()[19]
json.dump(dict(pid=os.getpid(), sessionId=sid, cwd=os.getcwd(), procStart=start, kind="interactive"),
          open(f"{home}/sessions/{os.getpid()}.json", "w"))
with open(os.path.expanduser("~/launches.log"), "a") as f:
    f.write(json.dumps(dict(kind="claude", sid=sid, argv=sys.argv, cwd=os.getcwd(),
                            base_url=os.environ.get("ANTHROPIC_BASE_URL"),
                            proxy=os.environ.get("HTTPS_PROXY"))) + "\n")
print(f"fake claude {sid}", flush=True)
while True:
    time.sleep(3600)
'''

FAKE_COPILOT = r'''#!/usr/bin/env python3
"""Fake copilot: writes the process log line and inuse lock like Copilot CLI."""
import json, os, sys, time, uuid
args = sys.argv[1:]
sid = None
for i, a in enumerate(args):
    if a in ("--resume", "-r") and i + 1 < len(args) and not args[i + 1].startswith("-"):
        sid = args[i + 1]
    if a.startswith("--resume="):
        sid = a.split("=", 1)[1]
sid = sid or str(uuid.uuid4())
home = os.path.expanduser("~/.copilot")
os.makedirs(f"{home}/logs", exist_ok=True)
os.makedirs(f"{home}/session-state/{sid}", exist_ok=True)
with open(f"/proc/{os.getpid()}/stat") as f:
    start = int(f.read().rsplit(")", 1)[1].split()[19])
btime = int(next(l for l in open("/proc/stat") if l.startswith("btime")).split()[1])
ms = (btime + start // os.sysconf("SC_CLK_TCK")) * 1000
with open(f"{home}/logs/process-{ms}-{os.getpid()}.log", "w") as f:
    f.write(f"2026-01-01T00:00:00.000Z [INFO] Registering foreground session: {sid}\n")
open(f"{home}/session-state/{sid}/inuse.{os.getpid()}.lock", "w").close()
with open(os.path.expanduser("~/launches.log"), "a") as f:
    f.write(json.dumps(dict(kind="copilot", sid=sid, argv=sys.argv, cwd=os.getcwd())) + "\n")
print(f"fake copilot {sid}", flush=True)
while True:
    time.sleep(3600)
'''

FAKE_SERVICE = r'''#!/usr/bin/env python3
"""Fake proxy: listens on --port."""
import json, os, socket, sys, time
port = int(sys.argv[sys.argv.index("--port") + 1])
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", port)); s.listen(8)
with open(os.path.expanduser("~/launches.log"), "a") as f:
    f.write(json.dumps(dict(kind="service", port=port, gh=os.environ.get("GH_CONFIG_DIR"))) + "\n")
while True:
    c, _ = s.accept(); c.close()
'''


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class Env:
    def __init__(self, tmp: Path):
        self.home = tmp / "home"
        self.bin = tmp / "bin"
        self.sock = f"actest-{uuid.uuid4().hex[:10]}"
        for d in (self.home / ".claude/sessions", self.home / ".copilot/logs", self.bin):
            d.mkdir(parents=True, exist_ok=True)
        for name, body in (("claude", FAKE_CLAUDE), ("copilot", FAKE_COPILOT), ("fakeproxy", FAKE_SERVICE)):
            p = self.bin / name
            p.write_text(body)
            p.chmod(0o755)
        conf = tmp / "tmux.conf"
        conf.write_text("set -g base-index 1\nset -g pane-base-index 1\nset -g default-shell /bin/bash\n"
                        "set -g default-command 'exec /bin/bash --noprofile --norc'\nset -g exit-empty on\n")
        self.conf = str(conf)
        self.port = free_port()
        cfg = tmp / "agentctl.json"
        cfg.write_text(json.dumps({"services": [{"name": "fakeproxy", "match": r"fakeproxy .*--port",
                                                 "env": ["GH_CONFIG_DIR"]}]}))
        self.env = {
            "HOME": str(self.home), "PATH": f"{self.bin}:/usr/bin:/bin", "LANG": "C.UTF-8",
            "AGENTCTL_STATE": str(tmp / "state"), "AGENTCTL_CONFIG": str(cfg),
            "AGENTCTL_TMUX_SOCKET": self.sock, "AGENTCTL_TMUX_CONF": self.conf,
            "AGENTCTL_PANE_SHELL": "/bin/bash", "AGENTCTL_NO_SCOPE": "1", "AGENTCTL_IDLE_MIN_AGE": "3",
            "TERM": "xterm-256color", "SHELL": "/bin/bash",
        }

    def tmux(self, *args, check=True) -> str:
        r = subprocess.run([TMUX, "-L", self.sock, "-f", self.conf, *args], capture_output=True, text=True,
                           env=self.env)
        if check and r.returncode:
            raise AssertionError(f"tmux {args}: {r.stderr}")
        return r.stdout

    def agentctl(self, *args) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, str(AGENTCTL), *args], capture_output=True, text=True,
                              env=self.env, timeout=120)

    def send(self, target: str, line: str) -> None:
        self.tmux("send-keys", "-t", target, line, "Enter")

    def launches(self) -> list[dict]:
        p = self.home / "launches.log"
        return [json.loads(l) for l in p.read_text().splitlines()] if p.exists() else []

    def wait(self, pred, timeout=15.0, what=""):
        end = time.time() + timeout
        while time.time() < end:
            if pred():
                return
            time.sleep(0.2)
        raise AssertionError(f"timed out waiting for {what}")

    def kill_server(self):
        self.tmux("kill-server", check=False)
        self.wait(lambda: subprocess.run([TMUX, "-L", self.sock, "ls"], capture_output=True).returncode != 0,
                  what="server exit")


@pytest.fixture
def env(tmp_path):
    if not TMUX:
        pytest.skip("tmux not installed")
    e = Env(tmp_path)
    yield e
    e.tmux("kill-server", check=False)
    subprocess.run(["pkill", "-f", str(e.bin)], capture_output=True)
    Path(f"/tmp/tmux-{os.getuid()}/{e.sock}").unlink(missing_ok=True)


def build_layout(e: Env) -> dict:
    """work:1 claude(proxy env), work:2 [copilot | shell], svc:1 proxy, scratch:3 idle shell."""
    e.tmux("new-session", "-d", "-s", "work", "-x", "200", "-y", "50", "-c", str(e.home))
    e.tmux("rename-window", "-t", "work:1", "agent")
    e.send("work:1", f"cd {e.home} && ANTHROPIC_BASE_URL=http://127.0.0.1:{e.port} claude --model 'x[1m]' --continue")
    e.tmux("new-window", "-d", "-t", "work:2", "-n", "pair", "-c", "/tmp")
    e.send("work:2.1", "copilot --yolo")
    e.tmux("split-window", "-d", "-h", "-t", "work:2", "-c", "/tmp")
    e.tmux("new-session", "-d", "-s", "svc", "-x", "200", "-y", "50", "-c", str(e.home))
    e.send("svc:1", f"GH_CONFIG_DIR=/tmp/ghx fakeproxy serve --port {e.port}")
    e.tmux("new-session", "-d", "-s", "scratch", "-c", "/tmp")
    e.tmux("move-window", "-s", "scratch:1", "-t", "scratch:3")
    e.wait(lambda: len([l for l in e.launches() if l["kind"] in ("claude", "copilot")]) == 2, what="agents")
    e.wait(lambda: any(l["kind"] == "service" for l in e.launches()), what="service")
    ids = {l["kind"]: l["sid"] for l in e.launches() if l["kind"] in ("claude", "copilot")}
    (e.home / "launches.log").unlink()
    return ids


def test_snapshot_records_exact_ids_services_and_env(env):
    ids = build_layout(env)
    r = env.agentctl("snapshot")
    assert r.returncode == 0, r.stderr
    m = json.loads((Path(env.env["AGENTCTL_STATE"]) / "current.json").read_text())
    by = {f"{p['session']}:{p['window']}.{p['pane']}": p for p in m["panes"]}
    assert by["work:1.1"]["agent"]["session_id"] == ids["claude"]
    assert by["work:1.1"]["agent"]["env"]["ANTHROPIC_BASE_URL"] == f"http://127.0.0.1:{env.port}"
    assert by["work:2.1"]["agent"]["session_id"] == ids["copilot"]
    assert by["work:2.2"]["agent"] is None and not by["work:2.2"]["busy"]
    svc = by["svc:1.1"]["service"]
    assert svc["port"] == env.port and svc["env"] == {"GH_CONFIG_DIR": "/tmp/ghx"}
    assert by["scratch:3.1"]["window"] == 3


def test_restore_after_server_loss(env):
    ids = build_layout(env)
    assert env.agentctl("snapshot").returncode == 0
    env.kill_server()
    subprocess.run(["pkill", "-f", str(env.bin)], capture_output=True)
    time.sleep(0.5)
    r = env.agentctl("tick")
    assert r.returncode == 0, r.stdout + r.stderr
    env.wait(lambda: len([l for l in env.launches() if l["kind"] in ("claude", "copilot")]) == 2, what="resumes")
    got = {l["kind"]: l for l in env.launches()}
    assert got["claude"]["sid"] == ids["claude"] and got["copilot"]["sid"] == ids["copilot"]
    assert got["claude"]["base_url"] == f"http://127.0.0.1:{env.port}"
    assert "--continue" not in got["claude"]["argv"] and "x[1m]" in got["claude"]["argv"]
    assert got["claude"]["cwd"] == str(env.home)
    svc = [l for l in env.launches() if l["kind"] == "service"]
    assert svc and svc[0]["gh"] == "/tmp/ghx"
    order = [l["kind"] for l in env.launches()]
    assert order.index("service") < order.index("claude"), order
    sessions = env.tmux("list-sessions", "-F", "#{session_name}").split()
    assert sorted(sessions) == ["scratch", "svc", "work"]
    wins = env.tmux("list-windows", "-t", "=work", "-F", "#{window_index}:#{window_name}").split()
    assert wins == ["1:agent", "2:pair"]
    assert env.tmux("list-windows", "-t", "=scratch", "-F", "#{window_index}").split() == ["3"]
    assert len(env.tmux("list-panes", "-t", "=work:2", "-F", "#{pane_id}").split()) == 2
    assert env.tmux("display", "-p", "-t", "=work:2.2", "#{pane_current_path}").strip() == "/tmp"


def test_restore_is_idempotent(env):
    build_layout(env)
    env.agentctl("snapshot")
    env.kill_server()
    subprocess.run(["pkill", "-f", str(env.bin)], capture_output=True)
    env.agentctl("restore")
    env.wait(lambda: len([l for l in env.launches() if l["kind"] in ("claude", "copilot")]) == 2, what="resumes")
    time.sleep(1)
    r = env.agentctl("restore")
    assert "nothing to restore" in r.stdout, r.stdout
    r = env.agentctl("tick")
    assert r.returncode == 0
    time.sleep(1)
    assert len([l for l in env.launches() if l["kind"] in ("claude", "copilot")]) == 2


def test_never_touches_busy_or_running(env):
    ids = build_layout(env)
    env.agentctl("snapshot")
    r = env.agentctl("restore", "--into-running", "-n")
    assert "nothing to restore" in r.stdout and "resume " not in r.stdout, r.stdout
    pid_before = env.tmux("display", "-p", "-t", "=work:1.1", "#{pane_pid}")
    env.agentctl("restore", "--into-running")
    assert env.tmux("display", "-p", "-t", "=work:1.1", "#{pane_pid}") == pid_before
    assert not [l for l in env.launches() if l["kind"] in ("claude", "copilot")]


def test_running_elsewhere_is_not_duplicated(env):
    ids = build_layout(env)
    env.agentctl("snapshot")
    env.tmux("kill-session", "-t", "=work")   # session gone, but move the claude elsewhere first
    env.send("scratch:3", f"claude --resume {ids['claude']}")
    env.wait(lambda: any(l["kind"] == "claude" for l in env.launches()), what="manual resume")
    r = env.agentctl("restore", "-n")
    assert f"claude {ids['claude'][:8]} already running elsewhere" in r.stdout, r.stdout
    assert f"--yolo --resume {ids['copilot']}" in r.stdout


def test_idle_pane_gets_agent_only_with_into_running(env):
    ids = build_layout(env)
    time.sleep(3)
    env.agentctl("snapshot")
    env.send("work:1.1", "C-c")
    subprocess.run(["pkill", "-f", f"{env.bin}/claude"], capture_output=True)
    env.wait(lambda: env.tmux("display", "-p", "-t", "=work:1.1", "#{pane_current_command}").strip() == "bash",
             what="claude exit")
    assert "nothing to restore" in env.agentctl("restore", "-n").stdout
    r = env.agentctl("restore", "--into-running")
    env.wait(lambda: any(l["kind"] == "claude" for l in env.launches()), what="resume into idle pane")
    assert [l["sid"] for l in env.launches() if l["kind"] == "claude"] == [ids["claude"]]


def test_duplicate_session_in_two_panes_resumed_once(env):
    sid = str(uuid.uuid4())
    env.tmux("new-session", "-d", "-s", "d", "-c", "/tmp")
    env.send("d:1", f"claude --resume {sid}")
    env.tmux("new-window", "-d", "-t", "d:2", "-c", "/tmp")
    env.send("d:2", f"claude --resume {sid}")
    env.wait(lambda: len(env.launches()) == 2, what="two claudes")
    env.agentctl("snapshot")
    assert "open in 2 panes" in env.agentctl("status").stdout
    env.kill_server()
    subprocess.run(["pkill", "-f", str(env.bin)], capture_output=True)
    (env.home / "launches.log").unlink()
    r = env.agentctl("restore")
    assert "was open in two panes; resumed once" in r.stdout, r.stdout
    env.wait(lambda: len(env.launches()) >= 1, what="resume")
    time.sleep(1)
    assert len(env.launches()) == 1


def test_stale_copilot_lock_removed(env):
    ids = build_layout(env)
    env.agentctl("snapshot")
    env.kill_server()
    subprocess.run(["pkill", "-9", "-f", str(env.bin)], capture_output=True)
    locks = list((env.home / f".copilot/session-state/{ids['copilot']}").glob("inuse.*.lock"))
    assert locks
    r = env.agentctl("restore")
    assert all(not l.exists() for l in locks), r.stdout


def test_snapshot_without_server_keeps_manifest(env):
    build_layout(env)
    env.agentctl("snapshot")
    cur = Path(env.env["AGENTCTL_STATE"]) / "current.json"
    before = cur.read_text()
    env.kill_server()
    env.agentctl("snapshot")
    assert cur.read_text() == before


def test_paused_tick_does_not_restore(env):
    build_layout(env)
    env.agentctl("snapshot")
    env.agentctl("pause")
    env.kill_server()
    env.agentctl("tick")
    assert subprocess.run([TMUX, "-L", env.sock, "ls"], capture_output=True).returncode != 0
    env.agentctl("unpause")
    env.agentctl("tick")
    assert subprocess.run([TMUX, "-L", env.sock, "ls"], capture_output=True).returncode == 0


def test_lost_lists_resume_command(env):
    ids = build_layout(env)
    env.agentctl("snapshot")
    subprocess.run(["pkill", "-f", f"{env.bin}/copilot"], capture_output=True)
    time.sleep(0.5)
    out = env.agentctl("lost").stdout
    assert ids["copilot"] in out and f"--resume {ids['copilot']}" in out
    assert ids["claude"] not in out


def test_history_and_restore_at(env):
    build_layout(env)
    env.agentctl("snapshot")
    first = env.agentctl("history").stdout.split()[0]
    time.sleep(1.1)
    env.tmux("kill-session", "-t", "=scratch")
    env.agentctl("snapshot")
    assert len(env.agentctl("history").stdout.splitlines()) == 2
    r = env.agentctl("restore", "-n", "--at", first)
    assert "scratch:3.1" in r.stdout


def test_replaced_server_gets_missing_panes_and_agents(env):
    """Server replaced (reboot + bare `tmux`, or a resurrect layout restore without agents)."""
    ids = build_layout(env)
    env.agentctl("snapshot")
    env.kill_server()
    subprocess.run(["pkill", "-f", str(env.bin)], capture_output=True)
    env.tmux("new-session", "-d", "-s", "0", "-c", "/tmp")             # what a bare `tmux` creates
    env.tmux("new-session", "-d", "-s", "work", "-x", "200", "-y", "50", "-c", str(env.home))  # layout-only
    time.sleep(3.5)                                                       # shells settle (IDLE_MIN_AGE=3)
    r = env.agentctl("tick")
    assert r.returncode == 0, r.stderr
    env.wait(lambda: len([l for l in env.launches() if l["kind"] in ("claude", "copilot")]) == 2, what="resumes")
    assert {l["sid"] for l in env.launches() if l["kind"] in ("claude", "copilot")} == set(ids.values())
    assert sorted(env.tmux("list-sessions", "-F", "#{session_name}").split()) == ["0", "scratch", "svc", "work"]
    time.sleep(1)
    env.agentctl("tick")
    env.agentctl("tick")
    time.sleep(1)
    assert len([l for l in env.launches() if l["kind"] in ("claude", "copilot")]) == 2, "restored twice"


def test_replaced_server_never_touches_busy_panes(env):
    build_layout(env)
    env.agentctl("snapshot")
    env.kill_server()
    subprocess.run(["pkill", "-f", str(env.bin)], capture_output=True)
    env.tmux("new-session", "-d", "-s", "work", "-x", "200", "-y", "50", "-c", str(env.home))
    env.send("work:1", "sleep 600")
    env.wait(lambda: env.tmux("display", "-p", "-t", "=work:1.1", "#{pane_current_command}").strip() == "sleep",
             what="busy pane")
    env.agentctl("tick")
    time.sleep(2)
    assert env.tmux("display", "-p", "-t", "=work:1.1", "#{pane_current_command}").strip() == "sleep"
    assert not [l for l in env.launches() if l["kind"] == "claude"]
    assert [l for l in env.launches() if l["kind"] == "copilot"]


@pytest.mark.skipif(subprocess.run(["systemctl", "--user", "is-system-running"], capture_output=True).returncode
                    not in (0, 1), reason="needs systemd --user")
def test_server_started_from_systemd_service_survives_it(env, tmp_path):
    """tick runs as a oneshot unit; the tmux server it starts must outlive that unit."""
    build_layout(env)
    env.agentctl("snapshot")
    env.kill_server()
    subprocess.run(["pkill", "-f", str(env.bin)], capture_output=True)
    unit = f"agentctl-test-{uuid.uuid4().hex[:8]}.service"
    udir = Path.home() / ".config/systemd/user"
    envs = {k: v for k, v in env.env.items() if k != "AGENTCTL_NO_SCOPE"}
    (udir / unit).write_text("[Service]\nType=oneshot\n"
                             + "".join(f"Environment={k}={v}\n" for k, v in envs.items())
                             + f"ExecStart={sys.executable} {AGENTCTL} tick\n")
    try:
        subprocess.run(["systemctl", "--user", "daemon-reload"], check=True)
        r = subprocess.run(["systemctl", "--user", "start", unit], capture_output=True, text=True, timeout=120)
        assert r.returncode == 0, r.stderr
        time.sleep(2)                              # oneshot finished; its cgroup is gone
        state = subprocess.run(["systemctl", "--user", "is-active", unit], capture_output=True, text=True).stdout
        assert state.strip() == "inactive"
        assert subprocess.run([TMUX, "-L", env.sock, "ls"], capture_output=True).returncode == 0, "server died with unit"
        env.wait(lambda: len([l for l in env.launches() if l["kind"] in ("claude", "copilot")]) == 2, what="resumes")
    finally:
        (udir / unit).unlink(missing_ok=True)
        subprocess.run(["systemctl", "--user", "daemon-reload"])


# ----------------------------------------------------------------------------- backup

@pytest.fixture
def bk(tmp_path, monkeypatch):
    home = tmp_path / "home"
    proj = home / ".claude/projects/-w"
    proj.mkdir(parents=True)
    (home / ".copilot/session-state").mkdir(parents=True)
    env = {"HOME": str(home), "AGENTCTL_STATE": str(tmp_path / "state"), "AGENTCTL_BACKUP": str(tmp_path / "bk"),
           "AGENTCTL_TMUX_SOCKET": f"none-{uuid.uuid4().hex[:6]}", "PATH": os.environ["PATH"]}
    run = lambda *a: subprocess.run([sys.executable, str(AGENTCTL), *a], capture_output=True, text=True, env=env)
    return home, proj, run, tmp_path / "bk"


def test_backup_is_incremental_and_recovers(bk):
    home, proj, run, store = bk
    sid = str(uuid.uuid4())
    t = proj / f"{sid}.jsonl"
    sub = proj / sid / "subagents"
    sub.mkdir(parents=True)
    (sub / "agent-a.jsonl").write_text('{"x":1}\n')
    t.write_bytes(b"".join(b'{"n":%d,"pad":"%s"}\n' % (i, b"y" * 200) for i in range(30000)))
    v1 = t.read_bytes()
    assert run("backup").returncode == 0
    shards1 = sorted((store / "objects").rglob("*.zst"))
    t.open("ab").write(b'{"n":"more"}\n' * 10)
    v2 = t.read_bytes()
    time.sleep(1.1)
    assert run("backup").returncode == 0
    new = sorted(set((store / "objects").rglob("*.zst")) - set(shards1))
    assert len(new) == 1 and new[0].stat().st_size < 200, "second run must store only the appended tail"
    idx = sorted((store / "index").glob("*.json"))
    assert len(idx) == 2
    t.unlink()
    shutil.rmtree(proj / sid)
    r = run("recover", sid)
    assert r.returncode == 0, r.stdout + r.stderr
    assert t.read_bytes() == v2 and (sub / "agent-a.jsonl").read_text() == '{"x":1}\n'
    t.write_bytes(b"corrupted")
    r = run("recover", sid, "--at", idx[0].stem)
    assert r.returncode == 0, r.stdout + r.stderr
    assert t.read_bytes() == v1
    assert list(proj.glob(f"{sid}.jsonl.pre-recover-*"))


def test_backup_rewrite_starts_new_chain(bk):
    home, proj, run, store = bk
    sid = str(uuid.uuid4())
    t = proj / f"{sid}.jsonl"
    t.write_text('{"a":1}\n' * 1000)
    run("backup")
    t.write_text('{"b":2}\n' * 500)            # rewritten in place, shorter
    time.sleep(1.1)
    run("backup")
    t.unlink()
    assert run("recover", sid).returncode == 0
    assert t.read_text() == '{"b":2}\n' * 500


def test_backup_keeps_deleted_files_and_refuses_running(bk):
    home, proj, run, store = bk
    sid = str(uuid.uuid4())
    t = proj / f"{sid}.jsonl"
    t.write_text('{"a":1}\n')
    run("backup")
    t.unlink()
    time.sleep(1.1)
    run("backup")                                # file gone: must stay in the new index
    last = sorted((store / "index").glob("*.json"))[-1]
    entry = json.loads(last.read_text())["files"][str(t)]
    assert entry.get("deleted_at")
    assert run("recover", sid).returncode == 0 and t.read_text() == '{"a":1}\n'


def test_backup_same_size_rewrite_and_growth_of_small_file(bk):
    """Reviewer cases: same-length in-place edit; small non-jsonl file growing past 1 MiB."""
    home, proj, run, store = bk
    sid = str(uuid.uuid4())
    t = proj / f"{sid}.jsonl"
    body = b"".join(b'{"i":%d,"s":"pending"}\n' % i for i in range(80000))
    t.write_bytes(body)
    run("backup")
    with open(t, "r+b") as f:                    # same length, same inode, bytes changed mid-file
        f.seek(len(body) // 2)
        f.write(b'"running"'[: 9])
    time.sleep(1.1)
    os.utime(t, None)
    run("backup")
    want = t.read_bytes()
    w = proj / sid / "workflows" / "wf.json"
    w.parent.mkdir(parents=True)
    w.write_text('{"a":1}')
    run("backup")
    w.write_text('{"a":"' + "z" * (2 << 20) + '"}')
    time.sleep(1.1)
    r = run("backup")
    assert r.returncode == 0, r.stdout + r.stderr
    t.unlink()
    shutil.rmtree(proj / sid)
    assert run("recover", sid).returncode == 0
    assert t.read_bytes() == want
    assert w.read_text().startswith('{"a":"zz') and w.stat().st_size > 2 << 20


def test_backup_partial_last_line_and_unreadable_file(bk):
    home, proj, run, store = bk
    sid = str(uuid.uuid4())
    t = proj / f"{sid}.jsonl"
    t.write_bytes(b'{"a":1}\n' * 200000 + b'{"partial":')
    bad = proj / sid / "tool-results" / "x.txt"
    bad.parent.mkdir(parents=True)
    bad.write_text("secret")
    bad.chmod(0)
    r = run("backup")
    assert r.returncode == 0 and "1 errors" in r.stdout, r.stdout + r.stderr
    t.open("ab").write(b'2}\n')
    time.sleep(1.1)
    run("backup")
    bad.chmod(0o600)
    full = t.read_bytes()
    t.unlink()
    assert run("recover", sid).returncode == 0
    assert t.read_bytes() == full


def test_failed_restore_is_not_retried_every_tick(env):
    """A restore that cannot finish must not loop; the snapshot must still advance."""
    build_layout(env)
    env.agentctl("snapshot")
    env.kill_server()
    subprocess.run(["pkill", "-f", str(env.bin)], capture_output=True)
    (env.bin / "copilot").write_text("#!/bin/sh\nexit 1\n")           # resume will fail
    env.agentctl("tick")
    time.sleep(1)
    log = (Path(env.env["AGENTCTL_STATE"]) / "agentctl.log").read_text()
    assert log.count("restore from manifest") == 1
    for _ in range(3):
        env.agentctl("tick")
    log = (Path(env.env["AGENTCTL_STATE"]) / "agentctl.log").read_text()
    assert log.count("restore from manifest") == 1, log


def test_restore_does_not_move_attached_focus(env):
    """Panes added to an existing session must not change its active window/pane."""
    build_layout(env)
    env.agentctl("snapshot")
    env.tmux("kill-window", "-t", "=work:2")
    env.tmux("select-window", "-t", "=work:1")
    env.agentctl("restore")
    env.wait(lambda: any(l["kind"] == "copilot" for l in env.launches()), what="copilot resume")
    assert env.tmux("list-windows", "-t", "=work", "-F", "#{window_active}#{window_index}").split()[0] == "11"


def test_fresh_shell_in_existing_pane_is_left_alone(env):
    """--into-running must not respawn a pane whose shell just started (rc may still be running)."""
    ids = build_layout(env)
    env.agentctl("snapshot")
    subprocess.run(["pkill", "-f", f"{env.bin}/claude"], capture_output=True)
    env.tmux("respawn-pane", "-k", "-t", "=work:1.1")                # brand-new shell
    env.env["AGENTCTL_IDLE_MIN_AGE"] = "60"
    r = env.agentctl("restore", "--into-running")
    assert "shell still starting" in r.stdout, r.stdout
    assert not [l for l in env.launches() if l["kind"] == "claude"]


def test_snapshot_from_foreign_server_is_ignored(env, tmp_path):
    build_layout(env)
    env.agentctl("snapshot")
    cur = Path(env.env["AGENTCTL_STATE"]) / "current.json"
    before = cur.read_text()
    e = dict(env.env)
    e.pop("AGENTCTL_TMUX_SOCKET")
    e["TMUX"] = f"/tmp/tmux-{os.getuid()}/someprivate,1,0"
    subprocess.run([sys.executable, str(AGENTCTL), "snapshot"], env=e, capture_output=True)
    assert cur.read_text() == before
