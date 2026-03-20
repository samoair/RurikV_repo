# Kubernetes Debugging — Distroless Containers

## Overview

This homework demonstrates debugging techniques for distroless containers in Kubernetes. Distroless images contain only the application and its runtime dependencies — no shell, no package manager, no debugging tools. This makes them secure and lightweight but challenging to debug.

---

## 1. Deploy a Distroless Nginx Pod

### Manifest: `distroless-nginx.yaml`

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: distroless-nginx
  labels:
    app: distroless-nginx
spec:
  shareProcessNamespace: true
  containers:
  - name: nginx
    image: kyos0109/nginx-distroless
    ports:
    - containerPort: 80
```

`shareProcessNamespace: true` allows debug containers to see all processes in the pod (required for `kubectl debug --share-processes` and `strace`).

### Apply and verify:

```bash
kubectl apply -f distroless-nginx.yaml
kubectl get pod distroless-nginx -o wide
```

---

## 2. Ephemeral Debug Container (Shared PID Namespace)

Attach an ephemeral debug container that shares the PID namespace of the target pod:

```bash
kubectl debug -it distroless-nginx --image=nicolaka/netshoot --target=nginx --share-processes
```

Key flags:
- `--target=nginx` — the debug container joins the network and IPC namespaces of the `nginx` container
- `--share-processes` — enables `shareProcessNamespace: true` so the debug container can see all processes from the target container's PID namespace

### Access the distroless container's filesystem from the debug container:

```bash
# Inside the debug container:
ls -la /etc/nginx
```

Expected output:
```
drwxr-xr-x    1 root root  23 Jan  1  1970 .
drwxr-xr-x    1 root root   1 Jan  1  1970 ..
drwxr-xr-x    1 root root  29 Jan  1  1970 conf.d
-rw-r--r--    1 root root 1077 Jan  1  1970 fastcgi_params
-rw-r--r--    1 root root  78 Jan  1  1970 mime.types
lrwxrwxrwx    1 root root   0 Jan  1  1970 modules -> /usr/lib/nginx/modules
-rw-r--r--    1 root root 263 Jan  1  1970 nginx.conf
-rw-r--r--    1 root root  636 Jan  1  1970 win-utf
```

---

## 3. Network Traffic Capture with tcpdump

Start tcpdump inside the debug container:

```bash
# Inside the debug container:
tcpdump -nn -i any -e port 80
```

From another terminal, send requests to the pod:

```bash
# Port-forward and send requests:
kubectl port-forward pod/distroless-nginx 8080:80 &

curl -s http://localhost:8080
curl -s http://localhost:8080
curl -s http://localhost:8080
```

Expected tcpdump output:
```
tcpdump: verbose output suppressed, use -v for full decode
listening on any, link-type LINUX_SLL (Linux cooked), snapshot length 262144 bytes
12:34:56.789012 eth0  In  IP 10.244.0.1.54321 > 10.244.1.5.80: Flags [S], seq 123456789, win 65535
12:34:56.789456 eth0  Out IP 10.244.1.5.80 > 10.244.0.1.54321: Flags [S.], seq 987654321, ack 123456790
12:34:56.789789 eth0  In  IP 10.244.0.1.54321 > 10.244.1.5.80: Flags [.], ack 987654322
12:34:56.790123 eth0  In  IP 10.244.0.1.54321 > 10.244.1.5.80: Flags [P.], len 75
12:34:56.790456 eth0  Out IP 10.244.1.5.80 > 10.244.0.1.54321: Flags [.], ack 76
12:34:56.791234 eth0  Out IP 10.244.1.5.80 > 10.244.0.1.54321: Flags [P.], len 244
12:34:56.791567 eth0  In  IP 10.244.0.1.54321 > 10.244.1.5.80: Flags [.], ack 245
```

---

## 4. Node-Level Debug Pod

Create a debug pod on the same node as the distroless nginx pod to access the node's filesystem and container logs:

```bash
# Find which node the pod is running on:
NODE_NAME=$(kubectl get pod distroless-nginx -o jsonpath='{.spec.nodeName}')
echo "Pod is running on node: $NODE_NAME"

# Create a node-level debug pod:
kubectl debug node/$NODE_NAME -it --image=nicolaka/netshoot --profile=sysadmin
```

The `--profile=sysadmin` flag grants privileged access to the host filesystem.

### Access pod logs from the node:

```bash
# Inside the node debug pod:
# Find the container ID:
CONTAINER_ID=$(crictl ps | grep nginx | awk '{print $1}')
echo "Container ID: $CONTAINER_ID"

# Read container logs:
cat /var/log/containers/distroless-nginx_*.log

# Or find and read from the CRI log directory:
cat /var/log/pods/default_distroless-nginx_*/nginx/0.log
```

Expected log output:
```
10.244.0.1 - - [20/Mar/2026:12:34:56 +0000] "GET / HTTP/1.1" 200 612 "-" "curl/8.x.x" "-"
10.244.0.1 - - [20/Mar/2026:12:34:57 +0000] "GET / HTTP/1.1" 200 612 "-" "curl/8.x.x" "-"
10.244.0.1 - - [20/Mar/2026:12:34:58 +0000] "GET / HTTP/1.1" 200 612 "-" "curl/8.x.x" "-"
```

---

## 5. Bonus: strace on the Nginx Process

`strace` traces system calls made by a process.

### Why plain `kubectl debug` doesn't work

Running `strace -p 1` inside an ephemeral debug container fails with:
```
strace: attach: ptrace(PTRACE_SEIZE, 1): Operation not permitted
```

**Root cause**: `kubectl debug` creates the ephemeral container with a default security context. The default AppArmor and seccomp profiles (`runtime/default`) block the `ptrace` syscall regardless of capabilities. Setting `SYS_PTRACE` on the nginx container does not help — `strace` runs in the debug container, which needs its own elevated privileges.

`kubectl debug` has no `--privileged` flag for pod debugging, and `kubectl proxy`+`curl` PATCH to the `ephemeralcontainers` subresource may not work on all Kubernetes versions/distributions.

### Solution: Use the node-level debug pod

Since the node debug pod (from step 4) is already privileged via `--profile=sysadmin`, we can run `strace` from there. The key steps:

1. **Node debug pod must be privileged** — granted by `--profile=sysadmin`
2. **Find the nginx process host PID** — use `pidof nginx` inside the node debug pod (hostPID is shared)
3. **Trace the worker process** — nginx master delegates connections to workers; `strace` on the master shows no I/O during requests

### Steps:

```bash
# Step 1: Get the pod IP (needed for requests from the node debug pod)
POD_IP=$(kubectl get pod distroless-nginx -o jsonpath='{.status.podIP}')

# Step 2: Get the node name
NODE_NAME=$(kubectl get pod distroless-nginx -o jsonpath='{.spec.nodeName}')

# Step 3: Create a privileged node debug pod that stays running
kubectl run node-strace --image=nicolaka/netshoot --restart=Never --overrides='{
  "spec": {
    "nodeName": "'$NODE_NAME'",
    "hostPID": true,
    "hostNetwork": true,
    "tolerations": [{"operator": "Exists"}],
    "containers": [{
      "name": "node-strace",
      "image": "nicolaka/netshoot",
      "command": ["sleep", "3600"],
      "securityContext": {"privileged": true}
    }]
  }
}'

kubectl wait --for=condition=Ready pod/node-strace --timeout=30s

# Step 4: Exec into it — find nginx PIDs, strace the worker, send requests
kubectl exec node-strace -- bash -c '
  WORKER_PID=$(pidof -s nginx-worker || pidof nginx | tr " " "\n" | tail -1)
  echo "=== Nginx worker host PID: $WORKER_PID ==="

  strace -p $WORKER_PID -e trace=network,read,write > /tmp/strace.out 2>&1 &
  STRACE_PID=$!
  sleep 2

  echo "=== Sending 3 requests ==="
  curl -s -o /dev/null -w "Request 1: HTTP %{http_code}\n" http://'$POD_IP'
  curl -s -o /dev/null -w "Request 2: HTTP %{http_code}\n" http://'$POD_IP'
  curl -s -o /dev/null -w "Request 3: HTTP %{http_code}\n" http://'$POD_IP'

  sleep 3
  kill $STRACE_PID 2>/dev/null; wait $STRACE_PID 2>/dev/null

  echo ""
  echo "=== strace output ==="
  cat /tmp/strace.out
'
```

### Actual strace output:

```
=== Nginx worker host PID: 11635 ===
=== Sending 3 requests ===
Request 1: HTTP 200
Request 2: HTTP 200
Request 3: HTTP 200

=== strace output ===
strace: Process 11635 attached
accept4(6, {sa_family=AF_INET, sin_port=htons(60668), sin_addr=inet_addr("10.112.129.1")}, [112 => 16], SOCK_NONBLOCK) = 3
recvfrom(3, "GET / HTTP/1.1\r\nHost: 10.112.129"..., 1024, 0, NULL, NULL) = 77
sendfile(3, 11, [0] => [612], 612)      = 612
write(5, "10.112.129.1 - - [21/Mar/2026:05"..., 93) = 93
setsockopt(3, SOL_TCP, TCP_NODELAY, [1], 4) = 0
recvfrom(3, "", 1024, 0, NULL, NULL)    = 0
accept4(6, {sa_family=AF_INET, sin_port=htons(60670), sin_addr=inet_addr("10.112.129.1")}, [112 => 16], SOCK_NONBLOCK) = 3
recvfrom(3, "GET / HTTP/1.1\r\nHost: 10.112.129"..., 1024, 0, NULL, NULL) = 77
sendfile(3, 11, [0] => [612], 612)      = 612
write(5, "10.112.129.1 - - [21/Mar/2026:05"..., 93) = 93
setsockopt(3, SOL_TCP, TCP_NODELAY, [1], 4) = 0
recvfrom(3, "", 1024, 0, NULL, NULL)    = 0
accept4(6, {sa_family=AF_INET, sin_port=htons(60684), sin_addr=inet_addr("10.112.129.1")}, [112 => 16], SOCK_NONBLOCK) = 3
recvfrom(3, "GET / HTTP/1.1\r\nHost: 10.112.129"..., 1024, 0, NULL, NULL) = 77
sendfile(3, 11, [0] => [612], 612)      = 612
write(5, "10.112.129.1 - - [21/Mar/2026:05"..., 93) = 93
setsockopt(3, SOL_TCP, TCP_NODELAY, [1], 4) = 0
recvfrom(3, "", 1024, 0, NULL, NULL)    = 0
strace: Process 11635 detached
```

Each request shows the full cycle:
1. `accept4` — accept the incoming connection
2. `recvfrom` — read the HTTP request
3. `sendfile` — serve the static file (zero-copy)
4. `write` — write the access log
5. `setsockopt(TCP_NODELAY)` — disable Nagle's algorithm before closing
6. `recvfrom` returns 0 — client closed connection

---

## Cleanup

```bash
kubectl delete pod distroless-nginx
kubectl delete pod node-strace --force --grace-period=0
```

---

## Tools Used

| Tool | Purpose |
|------|---------|
| `kubectl debug` | Creates ephemeral debug containers/pods |
| `nicolaka/netshoot` | Debug container image with full networking and debugging tools |
| `tcpdump` | Captures network packets |
| `strace` | Traces system calls and signals |
| `crictl` | Interacts with CRI-compatible container runtimes |
