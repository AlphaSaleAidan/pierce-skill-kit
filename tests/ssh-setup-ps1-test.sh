#!/bin/sh
# The Windows ssh-setup.ps1 against a real sshd, in PowerShell on Linux:
#   docker run --rm -v "$PWD:/kit:ro" mcr.microsoft.com/powershell:latest sh /kit/tests/ssh-setup-ps1-test.sh
set -e
apt-get update -qq >/dev/null && apt-get install -y -qq openssh-server openssh-client >/dev/null 2>&1
useradd -m -s /bin/bash srv && echo 'srv:server-pw' | chpasswd
useradd -m -s /bin/bash win
mkdir -p /run/sshd && printf 'Port 2222\nPasswordAuthentication yes\n' > /etc/ssh/sshd_config.d/t.conf && /usr/sbin/sshd
printf '#!/bin/sh\necho asked >> /tmp/asked; echo server-pw\n' > /usr/local/bin/pw; chmod 755 /usr/local/bin/pw
su win -s /bin/sh -c '
set -e
fail() { echo "FAIL: $*"; exit 1; }
export SSH_ASKPASS=/usr/local/bin/pw SSH_ASKPASS_REQUIRE=force DISPLAY=x
pwsh -NoProfile -File /kit/bin/windows/ssh-setup.ps1 srv@localhost -Port 2222 > /tmp/o1 2>&1 || { cat /tmp/o1; fail "first run"; }
[ -s /tmp/asked ] || fail "password never asked"
[ "$(ssh -o BatchMode=yes box whoami)" = srv ] || fail "no passwordless login"
prof=$(pwsh -NoProfile -c "\$PROFILE.CurrentUserAllHosts")
grep -q "^function lead { ssh -t box" "$prof" && grep -q "^function tab " "$prof" || fail "shortcuts missing"
echo "ok: first run: key made and trusted, ssh box needs no password, lead/tab in the profile"
: > /tmp/asked
pwsh -NoProfile -File /kit/bin/windows/ssh-setup.ps1 srv@localhost -Port 2222 > /tmp/o2 2>&1 || { cat /tmp/o2; fail "second run"; }
[ ! -s /tmp/asked ] || fail "second run asked again"
[ "$(grep -c "^Host box" ~/.ssh/config)" = 1 ] && [ "$(grep -c "pierce-skill-kit ssh-setup" "$prof")" = 2 ] || fail "duplicated lines"
pwsh -NoProfile -c ". \"$prof\"; Get-Command lead, tab | Out-Null" || fail "profile does not load"
echo "ok: second run changes nothing; the profile loads"
'
[ "$(grep -c . /home/srv/.ssh/authorized_keys)" = 1 ] || { echo "FAIL: key added more than once"; exit 1; }
echo "ALL SSH-SETUP.PS1 TESTS PASSED"
