#!/bin/sh
# ssh-setup against a real sshd (password login on) in a throwaway container:
#   docker run --rm -v "$PWD:/kit:ro" debian:stable-slim sh /kit/tests/ssh-setup-test.sh
set -e
apt-get update -qq >/dev/null && apt-get install -y -qq openssh-server openssh-client >/dev/null 2>&1
useradd -m -s /bin/bash srv && echo 'srv:server-pw' | chpasswd     # the "server" account
useradd -m -s /bin/zsh jake 2>/dev/null || useradd -m jake           # the person's own computer account
mkdir -p /run/sshd && printf 'Port 2222\nPasswordAuthentication yes\nKbdInteractiveAuthentication yes\n' > /etc/ssh/sshd_config.d/t.conf
/usr/sbin/sshd
printf '#!/bin/sh\necho asked >> /tmp/asked; echo server-pw\n' > /usr/local/bin/pw; chmod 755 /usr/local/bin/pw   # types the password
su jake -s /bin/sh -c '
set -e
fail() { echo "FAIL: $*"; exit 1; }
export SSH_ASKPASS=/usr/local/bin/pw SSH_ASKPASS_REQUIRE=force DISPLAY=x SHELL=/bin/zsh
sh /kit/bin/ssh-setup srv@localhost -p 2222 > /tmp/out1 2>&1 || { cat /tmp/out1; fail "first run"; }
[ "$(wc -l < /tmp/asked)" -ge 1 ] || fail "password was never asked"
[ "$(ssh -o BatchMode=yes box whoami)" = srv ] || fail "no passwordless login"
grep -q "^lead() { ssh -t box" ~/.zshrc && grep -q "^tab() { ssh -t box" ~/.zshrc || fail "shortcuts missing"
echo "ok: first run made a key, put it on the server, ssh box works with no password, lead/tab shortcuts added"
: > /tmp/asked; echo "# my own line" >> ~/.zshrc
sh /kit/bin/ssh-setup srv@localhost -p 2222 > /tmp/out2 2>&1 || { cat /tmp/out2; fail "second run"; }
[ ! -s /tmp/asked ] || fail "second run asked for the password again"
[ "$(grep -c "^Host box" ~/.ssh/config)" = 1 ] || fail "config block duplicated"
[ "$(grep -c "pierce-skill-kit ssh-setup" ~/.zshrc)" = 2 ] && grep -q "# my own line" ~/.zshrc || fail "shortcuts duplicated or own lines lost"
echo "ok: second run changes nothing and asks nothing"
printf "Host mine\n  HostName example.com\n" >> ~/.ssh/config
sh /kit/bin/ssh-setup srv@localhost -p 2222 -n mine >/dev/null 2>&1 && fail "overwrote a Host the person wrote"
grep -q "HostName example.com" ~/.ssh/config || fail "own Host block changed"
echo "ok: refuses a name the person already uses"
'
[ "$(grep -c . /home/srv/.ssh/authorized_keys)" = 1 ] || { echo "FAIL: key added more than once"; exit 1; }
[ "$(stat -c %a /home/srv/.ssh/authorized_keys)" = 600 ] || { echo "FAIL: authorized_keys permissions"; exit 1; }
echo "ok: the server has the key once, with safe permissions"
echo "ALL SSH-SETUP TESTS PASSED"
