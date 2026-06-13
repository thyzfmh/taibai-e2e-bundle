# Taibai E2E Offline Bundle

离线打包工具，用于在无网络环境中部署太白（Taibai）E2E 测试集群。

## 内容

- **Docker 镜像** — K8s E2E 测试所需的全部 27 个镜像
- **太白二进制** — taibai-master, taibai-mm, taibai-cli (Linux x86_64, musl 静态链接)
- **E2E 脚本** — kind 集群搭建、组件热替换、测试运行等完整工具链

## 下载

从 [GitHub Releases](https://github.com/thyzfmh/taibai-e2e-bundle/releases) 下载分卷压缩包：

```
taibai-offline-bundle-linux-amd64-v0.1.0.tar.gz.part_aa
taibai-offline-bundle-linux-amd64-v0.1.0.tar.gz.part_ab
taibai-offline-bundle-linux-amd64-v0.1.0.tar.gz.part_ac
taibai-offline-bundle-linux-amd64-v0.1.0.tar.gz.part_ad
```

## 恢复

### 1. 合并并解压

```bash
cat taibai-offline-bundle-linux-amd64-v0.1.0.tar.gz.part_* | tar -xzf - -C /tmp
```

### 2. 安装 kind（未包含在离线包中）

```bash
curl -Lo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64
chmod +x /usr/local/bin/kind
```

### 3. 恢复镜像和二进制

```bash
cd /tmp/taibai-offline-bundle

# 加载 Docker 镜像
for tar_file in images/*.tar; do
  docker load -i "$tar_file"
done

# 安装太白二进制
sudo cp bin/taibai-* /usr/local/bin/
sudo chmod +x /usr/local/bin/taibai-*

# 安装 E2E 脚本
sudo mkdir -p /opt/taibai/hack/e2e-tool/scripts
sudo cp scripts/* /opt/taibai/hack/e2e-tool/scripts/
sudo chmod +x /opt/taibai/hack/e2e-tool/scripts/*.sh
```

### 4. 运行 E2E 测试

```bash
/opt/taibai/hack/e2e-tool/scripts/taibai-e2e.sh --help
```

## 镜像列表

| 镜像 | 用途 |
|------|------|
| registry.k8s.io/e2e-test-images/agnhost:2.55 | 多功能测试工具 |
| registry.k8s.io/e2e-test-images/agnhost:2.63.0 | 多功能测试工具 |
| registry.k8s.io/e2e-test-images/sample-apiserver:1.29.2 | API Server 测试 |
| registry.k8s.io/e2e-test-images/apparmor-loader:1.4 | AppArmor 测试 |
| registry.k8s.io/e2e-test-images/busybox:1.37.0-1 | 基础工具容器 |
| registry.k8s.io/e2e-test-images/ipc-utils:1.4 | IPC 测试 |
| registry.k8s.io/e2e-test-images/glibc-dns-testing:2.0.0 | DNS 测试 |
| registry.k8s.io/e2e-test-images/kitten:1.8 | 元数据测试 |
| registry.k8s.io/e2e-test-images/nautilus:1.8 | 元数据测试 |
| registry.k8s.io/e2e-test-images/nginx:1.15-4 | Web 服务器测试 |
| registry.k8s.io/e2e-test-images/nginx:1.27-0 | Web 服务器测试 |
| registry.k8s.io/e2e-test-images/node-perf/npb-ep:1.6.0 | 节点性能测试 |
| registry.k8s.io/e2e-test-images/node-perf/npb-is:1.7.0 | 节点性能测试 |
| registry.k8s.io/e2e-test-images/node-perf/pytorch-wide-deep:1.0.0 | 深度学习性能测试 |
| registry.k8s.io/e2e-test-images/nonewprivs:1.4 | 权限测试 |
| registry.k8s.io/e2e-test-images/nonroot:1.5 | 非特权用户测试 |
| registry.k8s.io/e2e-test-images/perl:5.26 | Perl 脚本测试 |
| registry.k8s.io/e2e-test-images/regression-issue-74839:1.4 | 回归测试 |
| registry.k8s.io/e2e-test-images/resource-consumer:1.14 | 资源消耗测试 |
| registry.k8s.io/e2e-test-images/volume/nfs:1.6.0 | NFS 存储测试 |
| registry.k8s.io/e2e-test-images/volume/iscsi:2.7 | iSCSI 存储测试 |
| registry.k8s.io/pause:3.10.1 | 基础设施 |
| registry.k8s.io/pause:3.10.2 | 基础设施 |
| registry.k8s.io/etcd:3.6.11-0 | 基础设施 |
| registry.k8s.io/build-image/distroless-iptables:v0.9.1 | 基础设施 |
| registry.k8s.io/sig-storage/nfs-provisioner:v4.0.8 | 存储供给 |
| registry.k8s.io/coredns/coredns:v1.14.2 | DNS 服务 |

## 注意事项

- 本离线包仅包含 **Linux x86_64** 架构的二进制和镜像
- `kind` 二进制未包含在内，需单独安装
- `kindest/node` 镜像未包含在内（体积过大），需单独拉取或构建
- 太白 ap/agent 组件尚未构建，后续版本会加入
