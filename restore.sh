#!/usr/bin/env bash
# restore.sh — 一键恢复太白 E2E 离线包
#
# 用法:
#   ./restore.sh                    # 交互式安装
#   ./restore.sh --skip-images      # 跳过镜像加载
#   ./restore.sh --skip-binaries    # 跳过二进制安装
#   ./restore.sh --bundle-dir /tmp  # 指定解压目录
#   ./restore.sh --version v0.1.0   # 指定版本 (默认: latest)
#
# 前置条件:
#   - curl, tar, docker
#   - 网络连接 (仅下载 Release 文件时需要)

set -euo pipefail

# ─── 配置 ─────────────────────────────────────────────────────────────
REPO="thyzfmh/taibai-e2e-bundle"
PLATFORM="linux-amd64"
VERSION="${RESTORE_VERSION:-latest}"
BUNDLE_DIR="${RESTORE_BUNDLE_DIR:-/tmp/taibai-offline-bundle}"
BIN_DIR="${RESTORE_BIN_DIR:-/usr/local/bin}"
SCRIPT_DIR="${RESTORE_SCRIPT_DIR:-/opt/taibai/hack/e2e-tool/scripts}"
SKIP_IMAGES=false
SKIP_BINARIES=false
SKIP_SCRIPTS=false
DOWNLOAD_ONLY=false

# ─── 日志 ─────────────────────────────────────────────────────────────
log_info()  { echo "[INFO]  $*"; }
log_ok()    { echo -e "\033[32m[OK]\033[0m    $*"; }
log_warn()  { echo -e "\033[33m[WARN]\033[0m  $*"; }
log_fail()  { echo -e "\033[31m[FAIL]\033[0m  $*"; }

# ─── 参数解析 ─────────────────────────────────────────────────────────
usage() {
  sed -n '2,12p' "$0"
  echo ""
  echo "选项:"
  echo "  --skip-images      跳过 Docker 镜像加载"
  echo "  --skip-binaries    跳过二进制安装"
  echo "  --skip-scripts     跳过脚本安装"
  echo "  --download-only    仅下载，不安装"
  echo "  --bundle-dir DIR   解压目录 (默认: /tmp/taibai-offline-bundle)"
  echo "  --bin-dir DIR      二进制安装目录 (默认: /usr/local/bin)"
  echo "  --version VER      版本号 (默认: latest)"
  echo "  -h, --help         显示帮助"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-images)    SKIP_IMAGES=true; shift ;;
    --skip-binaries)  SKIP_BINARIES=true; shift ;;
    --skip-scripts)   SKIP_SCRIPTS=true; shift ;;
    --download-only)  DOWNLOAD_ONLY=true; shift ;;
    --bundle-dir)     BUNDLE_DIR="$2"; shift 2 ;;
    --bin-dir)        BIN_DIR="$2"; shift 2 ;;
    --version)        VERSION="$2"; shift 2 ;;
    -h|--help)        usage ;;
    *)                log_fail "未知参数: $1"; usage ;;
  esac
done

# ─── 前置检查 ─────────────────────────────────────────────────────────
check_prereqs() {
  local missing=0
  for cmd in curl tar; do
    if ! command -v "$cmd" &>/dev/null; then
      log_fail "$cmd 未安装"
      missing=$((missing + 1))
    fi
  done
  if [[ "$SKIP_IMAGES" == "false" ]] && ! command -v docker &>/dev/null; then
    log_fail "docker 未安装 (使用 --skip-images 跳过)"
    missing=$((missing + 1))
  fi
  if [[ "$missing" -gt 0 ]]; then
    exit 1
  fi
}

# ─── 获取版本 ─────────────────────────────────────────────────────────
resolve_version() {
  if [[ "$VERSION" == "latest" ]]; then
    log_info "获取最新版本..."
    VERSION=$(gh release view --repo "$REPO" --json tagName -q '.tagName' 2>/dev/null || \
              curl -sL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
    if [[ -z "$VERSION" ]]; then
      log_fail "无法获取最新版本，请指定 --version"
      exit 1
    fi
  fi
  log_info "版本: ${VERSION}"
}

# ─── 下载分卷 ─────────────────────────────────────────────────────────
download_parts() {
  local download_dir="${BUNDLE_DIR%.offline-bundle}-download"
  mkdir -p "$download_dir"

  local prefix="taibai-offline-bundle-${PLATFORM}-${VERSION}.tar.gz.part_"
  local part_suffixes=("aa" "ab" "ac" "ad")

  # 检查哪些分卷已存在
  local need_download=()
  for suffix in "${part_suffixes[@]}"; do
    local part_file="${download_dir}/${prefix}${suffix}"
    if [[ -f "$part_file" ]]; then
      log_ok "${prefix}${suffix} 已存在，跳过下载"
    else
      need_download+=("$suffix")
    fi
  done

  if [[ ${#need_download[@]} -eq 0 ]]; then
    log_ok "所有分卷已下载"
    return
  fi

  local base_url="https://github.com/${REPO}/releases/download/${VERSION}"
  for suffix in "${need_download[@]}"; do
    local filename="${prefix}${suffix}"
    local url="${base_url}/${filename}"
    log_info "下载 ${filename}..."
    if ! curl -fSL --progress-bar -o "${download_dir}/${filename}" "$url"; then
      log_fail "下载失败: ${filename}"
      log_info "该分卷可能不存在 (包可能不足 4 个分卷)，尝试继续..."
      rm -f "${download_dir}/${filename}"
    fi
  done

  log_ok "下载完成: ${download_dir}"
}

# ─── 合并解压 ─────────────────────────────────────────────────────────
extract_bundle() {
  local download_dir="${BUNDLE_DIR%.offline-bundle}-download"
  local prefix="taibai-offline-bundle-${PLATFORM}-${VERSION}.tar.gz.part_"

  # 检查是否有分卷文件
  local parts=("${download_dir}/${prefix}"*)
  if [[ ${#parts[@]} -eq 0 ]] || [[ ! -f "${parts[0]}" ]]; then
    log_fail "未找到分卷文件: ${download_dir}/${prefix}*"
    exit 1
  fi

  log_info "合并并解压..."
  rm -rf "$BUNDLE_DIR"
  cat "${download_dir}/${prefix}"* | tar -xzf - -C "$(dirname "$BUNDLE_DIR")"
  log_ok "已解压到 ${BUNDLE_DIR}"
}

# ─── 加载镜像 ─────────────────────────────────────────────────────────
load_images() {
  if [[ "$SKIP_IMAGES" == "true" ]]; then
    log_info "跳过镜像加载"
    return
  fi

  local img_dir="${BUNDLE_DIR}/images"
  if [[ ! -d "$img_dir" ]]; then
    log_warn "镜像目录不存在: ${img_dir}"
    return
  fi

  local count=0
  local total=$(ls "${img_dir}"/*.tar 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$total" -eq 0 ]]; then
    log_warn "未找到镜像文件"
    return
  fi

  log_info "加载 ${total} 个 Docker 镜像 (可能需要几分钟)..."
  for tar_file in "${img_dir}"/*.tar; do
    [[ -f "$tar_file" ]] || continue
    count=$((count + 1))
    local name=$(basename "$tar_file" .tar | sed 's/_/\//g; s/_/\//g; s/_/:/' | head -1)
    echo -ne "  [${count}/${total}] 加载中...          \r"
    if docker load -i "$tar_file" &>/dev/null; then
      echo -ne "  [${count}/${total}] OK                  \n"
    else
      echo -ne "  [${count}/${total}] FAIL                 \n"
      log_warn "  $(basename "$tar_file" .tar) 加载失败"
    fi
  done
  log_ok "已加载 ${count}/${total} 个镜像"
}

# ─── 安装二进制 ───────────────────────────────────────────────────────
install_binaries() {
  if [[ "$SKIP_BINARIES" == "true" ]]; then
    log_info "跳过二进制安装"
    return
  fi

  local bin_src="${BUNDLE_DIR}/bin"
  if [[ ! -d "$bin_src" ]]; then
    log_warn "二进制目录不存在: ${bin_src}"
    return
  fi

  local count=0
  for bin in "${bin_src}"/*; do
    [[ -f "$bin" ]] || continue
    local name=$(basename "$bin")
    local dest="${BIN_DIR}/${name}"

    # 太白二进制放到 taibai target 目录 (如果有 TAIBAI_ROOT)
    if [[ "${name}" == taibai-* ]] && [[ -n "${TAIBAI_ROOT:-}" ]]; then
      local taibai_dest="${TAIBAI_ROOT}/target/x86_64-unknown-linux-musl/release/${name}"
      mkdir -p "$(dirname "$taibai_dest")"
      cp "$bin" "$taibai_dest"
      chmod +x "$taibai_dest"
      log_ok "  ${name} → ${taibai_dest}"
    else
      if [[ -w "$BIN_DIR" ]]; then
        cp "$bin" "$dest"
      else
        sudo cp "$bin" "$dest"
      fi
      chmod +x "$dest"
      log_ok "  ${name} → ${dest}"
    fi
    count=$((count + 1))
  done
  log_ok "已安装 ${count} 个二进制"
}

# ─── 安装脚本 ─────────────────────────────────────────────────────────
install_scripts() {
  if [[ "$SKIP_SCRIPTS" == "true" ]]; then
    log_info "跳过脚本安装"
    return
  fi

  local script_src="${BUNDLE_DIR}/scripts"
  if [[ ! -d "$script_src" ]]; then
    log_warn "脚本目录不存在: ${script_src}"
    return
  fi

  mkdir -p "$SCRIPT_DIR"
  cp "${script_src}"/* "${SCRIPT_DIR}/"
  chmod +x "${SCRIPT_DIR}/"*.sh 2>/dev/null || true
  log_ok "脚本已安装到 ${SCRIPT_DIR}"
}

# ─── 安装 kind (提示) ────────────────────────────────────────────────
install_kind_hint() {
  if command -v kind &>/dev/null; then
    log_ok "kind 已安装: $(kind version 2>/dev/null || echo 'unknown')"
    return
  fi

  log_warn "kind 未安装，请执行以下命令安装:"
  echo ""
  echo "  curl -Lo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64"
  echo "  chmod +x /usr/local/bin/kind"
  echo ""
}

# ─── 主流程 ───────────────────────────────────────────────────────────
main() {
  log_info "=== 太白 E2E 离线包恢复 ==="

  check_prereqs
  resolve_version
  download_parts
  extract_bundle

  if [[ "$DOWNLOAD_ONLY" == "true" ]]; then
    log_ok "仅下载模式，跳过安装"
    log_info "离线包位于: ${BUNDLE_DIR}"
    exit 0
  fi

  load_images
  install_binaries
  install_scripts
  install_kind_hint

  log_ok "=== 恢复完成 ==="
  log_info "下一步: ${SCRIPT_DIR}/taibai-e2e.sh --help"
}

main
