---
name: collab-sandbox
description: Give a collaborator (editor, contractor, teammate) a walled-off workspace on your server — their own browser IDE container where they run Claude Code under THEIR OWN Claude login, plus capped access to a paid generation API through a small proxy — without access to your files, keys, other projects or private network. Use for "give X access to the server", "sandbox for X", "onboard a collaborator", "let X use our image/video credits with a cap", changing someone's cap, or revoking access.
---

# Collab sandbox

Two pieces per collaborator. Neither one hands over your login or your API key.

| Piece | What it is |
|---|---|
| **IDE** | A container running a browser IDE (e.g. code-server) with Claude Code installed. The collaborator signs in to Claude with **their own account** (or a seat on your Team/Enterprise plan). They can add their own MCP connectors and plugins; it only affects their container. |
| **Capped proxy** (optional) | A small web service that holds your paid generation API key (image/video/voice) and exposes quote → generate → status to each person with a **per-person weekly credit cap**. Give it a web page and/or an MCP endpoint so their Claude can call it. The cap only protects calls that go through the proxy. |

**Never share your Claude login or subscription seat with another person**; that breaks Anthropic's
consumer terms. Each collaborator uses their own account; check Anthropic's terms for your plan.
Never hand out the generation vendor's login or key either; they get the proxy, nothing else.

## Isolation (the part that matters)
- Run as a non-root user, `--cap-drop ALL`, `--security-opt no-new-privileges`, memory/CPU/pids limits.
- A dedicated docker network, e.g. `docker network create --subnet 172.31.250.0/24 collabnet` (any unused private subnet; host side is `.1`).
- Firewall it: the containers may reach the internet and the proxy port only; every other host port and
  every private range is dropped (so no local databases, AI gateways, admin panels or LAN devices):
  ```sh
  N=172.31.250.0/24; PROXY_PORT=<proxy-port>
  iptables -N COLLAB-IN 2>/dev/null || iptables -F COLLAB-IN
  iptables -A COLLAB-IN -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  iptables -A COLLAB-IN -p tcp -d 172.31.250.1 --dport "$PROXY_PORT" -j ACCEPT
  iptables -A COLLAB-IN -p udp --dport 53 -j ACCEPT; iptables -A COLLAB-IN -p tcp --dport 53 -j ACCEPT
  iptables -A COLLAB-IN -j DROP
  iptables -C INPUT -s $N -j COLLAB-IN 2>/dev/null || iptables -I INPUT 1 -s $N -j COLLAB-IN
  for d in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10 <your-server-public-ip>/32; do
    iptables -C DOCKER-USER -s $N -d $d -j DROP 2>/dev/null || iptables -I DOCKER-USER 1 -s $N -d $d -j DROP
  done
  ```
  Run it from a systemd oneshot so it survives reboots and docker restarts.
- The proxy itself runs as its own system user with systemd hardening (`ProtectHome=yes`,
  `ProtectSystem=strict`, a `MemoryMax`), bound to the docker bridge address, not `0.0.0.0`.
- Mount nothing from your home directory. Shared read-only assets (brand kits) go in with `:ro`.

## Add a person
1. Proxy: create their user with a weekly cap → it prints an access code once. Store it in your
   secrets store (mode 600), never in chat or the repo.
2. Env file for the container (mode 600, outside any repo): `PASSWORD=<random>` for the IDE,
   `PROXY_URL=http://172.31.250.1:<proxy-port>`, their proxy user and code.
3. Start the IDE:
   ```sh
   docker run -d --name collab-ide-<name> --restart unless-stopped --network collabnet \
     --env-file <path-to-their-env> -v collab-<name>-home:/home/coder \
     --cap-drop ALL --security-opt no-new-privileges --memory 3g --cpus 2 --pids-limit 512 \
     -p 127.0.0.1:<host-port>:8080 <your-ide-image>
   ```
4. Expose it over HTTPS (your reverse proxy or a named tunnel; quick tunnels change URL on restart).
5. They open it, run `claude`, and `/login` with **their** account.
6. Connector (optional): give them the proxy's MCP URL to add in their own Claude
   (`claude mcp add --transport http <name> <url>`); test it with a real `claude -p --mcp-config` call
   (quote → generate → status) before you say it works.
7. Browser-test it yourself on phone and desktop width (log in, quote, screenshot) before sending the link.
8. Ask the human before sending the welcome message; links go out only after they return 200.

## Manage
- Usage and caps live in the proxy (usage report, change cap, rotate code).
- Revoke: disable their proxy user + `docker stop collab-ide-<name>` (the volume keeps their work).
- The proxy draws on your one vendor balance: check the account balance before raising anyone's cap.

## Gotchas
- Job results: read the vendor's status + result URL fields; input image URLs in the job payload are not outputs.
- Downloads served by the proxy should be signed, expiring links, not open paths.
- Keep the proxy's vendor login/refresh flow documented; a CLI upgrade can invalidate old device links.

Needs: a Linux server you control, Docker, iptables, a browser-IDE image with Claude Code, each collaborator's own Claude account; optional: a paid generation API behind a small proxy you write.
