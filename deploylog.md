# Deployment Success! ✅

It's all working!

## Summary of what's set up:

- ✅ Next.js app running in Docker on your Pi
- ✅ Nginx proxying `localhost:80` → `localhost:3000`
- ✅ Cloudflare Tunnel routing `hello.rioedwards.com` → `localhost:80`
- ✅ DNS resolving correctly (after cache flush)
- ✅ SSL/TLS handled by Cloudflare

Your Next.js app should now be accessible at:
**https://hello.rioedwards.com**

The deployment is complete. The site is accessible from anywhere via the Cloudflare Tunnel, and SSL is handled automatically by Cloudflare.

---

# What went wrong and how we solved it

Refer to these next time, so that you don't run into the same issues again:

## Issues and Solutions

### 1. Debian/Raspberry Pi OS compatibility

**Issue:** Script was written for Ubuntu, but Raspberry Pi runs Debian/Raspberry Pi OS

- `software-properties-common` doesn't exist on Debian
- `apt-key` is deprecated
- `add-apt-repository` doesn't exist

**Solution:**

- Detect OS and use Debian-compatible Docker installation
- Use modern GPG keyring method (`/etc/apt/keyrings`)
- Manually add Docker repository instead of `add-apt-repository`

### 2. Docker IPv6 connection failures

**Issue:** Docker trying to connect via IPv6, getting "network is unreachable" errors when pulling images

- Network doesn't support IPv6
- Docker was attempting IPv6 connections to registry

**Solution:**
Configure `/etc/docker/daemon.json`:

```json
{
  "ipv6": false,
  "fixed-cidr-v6": "",
  "dns": ["8.8.8.8", "8.8.4.4"]
}
```

- Restart Docker after configuration changes

### 3. DNS returning only IPv6 addresses

**Issue:** Router DNS (192.168.0.1) returning only IPv6 addresses for `registry-1.docker.io`

- Even with IPv6 disabled in Docker, system DNS lookups returned IPv6

**Solution:**

- Update `/etc/resolv.conf` to use Google DNS:
  ```
  nameserver 8.8.8.8
  nameserver 8.8.4.4
  ```
- Configure `/etc/gai.conf` to prefer IPv4:
  ```
  precedence ::ffff:0:0/96  100
  ```

### 4. Script complexity causing crashes

**Issue:** Added kernel-level IPv6 disabling via `sysctl` which crashed the Pi

- Too many complex fixes made debugging difficult

**Solution:**

- Removed dangerous `sysctl` commands
- Simplified script to only essential fixes
- DNS/gai.conf configuration is sufficient; no kernel-level changes needed

### 5. Cloudflare Tunnel route configuration

**Issue:** DNS record existed but tunnel ingress rule wasn't configured

- `cloudflared tunnel route dns` created DNS but didn't update tunnel ingress rules when using token-based auth

**Solution:**

- Use Cloudflare Dashboard: **Zero Trust → Networks → Tunnels → Published application routes**
- Add route via dashboard (creates both DNS and ingress together)
- Or create `~/.cloudflared/config.yml` with all routes if using config-based auth

### 6. Nginx showing default page

**Issue:** Nginx default site taking precedence over custom config

- Default site at `/etc/nginx/sites-enabled/default` was matching requests first

**Solution:**

```bash
sudo rm /etc/nginx/sites-enabled/default
sudo systemctl restart nginx
```

### 7. DNS cache on Mac

**Issue:** Mac's DNS cache had stale records after DNS changes

- `curl` couldn't resolve domain even though DNS was correct

**Solution:**
Flush DNS cache:

```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

---

## Prevention Checklist for Next Deployment

### Before running deploy script:

- [ ] Verify OS (Debian vs Ubuntu)
- [ ] Check if IPv6 works: `ping6 -c 1 2001:4860:4860::8888`
- [ ] Test DNS: `nslookup registry-1.docker.io` (check if it returns IPv4)

### After Docker installation:

- [ ] Verify IPv6 fix is applied: `cat /etc/docker/daemon.json`
- [ ] Test Docker pull: `sudo docker pull hello-world`

### After Cloudflare Tunnel setup:

- [ ] Verify route in dashboard (not just DNS record)
- [ ] Check tunnel logs: `sudo journalctl -u cloudflared | grep ingress`

### After nginx setup:

- [ ] Verify default site is disabled: `ls /etc/nginx/sites-enabled/`
- [ ] Test locally: `curl http://localhost:80`

### On client machines:

- [ ] Flush DNS cache if domain doesn't resolve
- [ ] Wait 5-15 minutes for DNS propagation if needed

---

**Note:** These fixes are now in the deploy script, so future deployments should avoid these issues.
