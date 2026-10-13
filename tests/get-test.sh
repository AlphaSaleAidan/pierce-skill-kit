#!/bin/sh
# One-liner end to end on a fresh Ubuntu/Debian container, as a non-root user with sudo:
#   docker run --rm -v "$PWD:/kit:ro" ubuntu:24.04 sh /kit/tests/get-test.sh
#   docker run --rm -v "$PWD:/kit:ro" debian:12   sh /kit/tests/get-test.sh
set -e
apt-get update -qq >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sudo curl ca-certificates git >/dev/null
useradd -m -s /bin/bash dev && echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev
cp -r /kit /tmp/src && rm -rf /tmp/src/.git && git -C /tmp/src init -q -b main 2>/dev/null; git -C /tmp/src add -A >/dev/null 2>&1; \
  git -C /tmp/src -c user.name=t -c user.email=t@example.com commit -qm t >/dev/null 2>&1 || true
chown -R dev /tmp/src
su - dev -c '
set -e
fail() { echo "FAIL: $*"; exit 1; }
export PSK_REPO=file:///tmp/src
cat /tmp/src/get.sh | bash -s -- --dry-run > /tmp/dry.log; grep -q "Dry run: nothing changed" /tmp/dry.log || fail "dry run"
[ ! -d ~/pierce-skill-kit ] && ! command -v tmux >/dev/null || fail "dry run changed something"
echo "ok: dry run shows the plan and changes nothing"
cat /tmp/src/get.sh | bash -s -- --yes > /tmp/run1.log 2>&1 || { tail -20 /tmp/run1.log; fail "get.sh --yes"; }
grep -q "+ sudo env DEBIAN_FRONTEND=noninteractive apt-get install" /tmp/run1.log || fail "sudo commands not shown"
echo "ok: one-liner installed everything ($(grep -c "^  + " /tmp/run1.log) commands shown)"
cat /tmp/src/get.sh | bash -s -- --yes > /tmp/run2.log 2>&1 || { tail -20 /tmp/run2.log; fail "second run"; }
grep -q "packages: all present" /tmp/run2.log && grep -q "Claude Code: present" /tmp/run2.log || fail "second run not idempotent"
echo "ok: second run is a no-op for deps"
bash -lc "lead doctor" > /tmp/doctor.log 2>&1 || { cat /tmp/doctor.log; fail "doctor"; }
echo "ok: lead doctor passes ($(grep -c "✓" /tmp/doctor.log) checks ok, $(grep -c "!" /tmp/doctor.log) warnings)"
bash -lc "claude --version" | grep -q "Claude Code" || fail "claude not on PATH"
cat /tmp/src/get.sh | bash -s -- --yes --vps --dry-run | grep -q "harden this server" || fail "vps plan"
echo "ok: --vps shows the hardening plan"
echo "ALL GET TESTS PASSED"
'
