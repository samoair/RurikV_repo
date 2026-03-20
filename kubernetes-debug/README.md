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
    securityContext:
      capabilities:
        add:
        - SYS_PTRACE
```

Key fields:
- `shareProcessNamespace: true` — all containers in the pod see each other's processes (required for `kubectl debug --share-processes` and `strace`)
- `SYS_PTRACE` capability — allows `ptrace()` syscalls needed by `strace`

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
-rw-r--r--    1 root root 636 Jan  1  1970 win-utf
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

## 5. Bonus: strace on the Nginx Master Process

`strace` traces system calls made by a process. To make it work, three things are needed:

1. **`shareProcessNamespace: true`** on the pod spec — so the debug container can see all processes.
2. **`SYS_PTRACE` capability** on the nginx container — without it, `ptrace()` calls fail with `Operation not permitted`.
3. **`strace` in the debug image** — `nicolaka/netshoot` includes it.

### Steps:

```bash
# Step 1: Delete and re-deploy the pod with the updated manifest
kubectl delete pod distroless-nginx
kubectl apply -f distroless-nginx.yaml

# Step 2: Attach a debug container with shared PID namespace
kubectl debug -it distroless-nginx --image=nicolaka/netshoot --target=nginx --share-processes

# Step 3: Find the nginx master process PID
ps aux | grep nginx
```

Expected:
```
root         1  0.0  0.1  12060  5648 ?        Ss   12:00   0:00 nginx: master process
```

```bash
# Step 4: Run strace on PID 1 (nginx master)
strace -p 1
```

Then, from another terminal, send a request:

```bash
kubectl port-forward pod/distroless-nginx 8080:80 &
curl -s http://localhost:8080
```

Expected strace output:
```
strace: Process 1 attached
epoll_wait(6, [{EPOLLIN, {u32=10, u64=10}}], 512, -1) = 1
accept4(10, {sa_family=AF_INET, sin_port=htons(54321), sin_addr=inet_addr("10.244.0.1")}, [112->16], SOCK_NONBLOCK|SOCK_CLOEXEC) = 11
epoll_ctl(6, EPOLL_CTL_ADD, 11, {EPOLLIN|EPOLLEXCLUSIVE|EPOLLRDHUP, {u32=11, u64=11}}) = 0
...
read(10, "GET / HTTP/1.1\r\nHost: localhost:8"..., 1024) = 75
...
write(10, "HTTP/1.1 200 OK\r\nServer: nginx/1."..., 244) = 244
```

---

## Cleanup

```bash
kubectl delete pod distroless-nginx
kubectl delete pod node-debugger-XXXXX  # replace with actual debug pod name
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
