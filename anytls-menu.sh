#!/bin/bash
# =============================================
# AnyTLS-Go Linux 服务端一键安装与管理脚本
# 功能：交互菜单 / 升级保留配置 / 随机密码 / 自定义或随机端口
# 项目：https://github.com/anytls/anytls-go
# =============================================

set -e

# ====================== 配置 ======================
INSTALL_BIN_DIR="/usr/local/bin"
SERVICE_NAME="anytls"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
DEFAULT_PORT=8443
PORT_MIN=1024
PORT_MAX=65535

# ====================== 颜色 ======================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${GREEN}[信息] $1${NC}"; }
warn() { echo -e "${YELLOW}[提示] $1${NC}"; }
error() { echo -e "${RED}[错误] $1${NC}"; return 1; }

# ====================== 通用检查 ======================
require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "请使用 root 或 sudo 运行此脚本"
        return 1
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

is_installed() {
    [ -f "${SERVICE_FILE}" ] && [ -x "${INSTALL_BIN_DIR}/anytls-server" ]
}

is_valid_port() {
    local port=$1
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge "$PORT_MIN" ] && [ "$port" -le "$PORT_MAX" ]
}

is_port_in_use() {
    local port=$1
    if command_exists ss; then
        ss -ltn | awk '{print $4}' | grep -Eq "[:\.]${port}$"
    elif command_exists netstat; then
        netstat -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:\.]${port}$"
    else
        return 1
    fi
}

get_service_execstart() {
    [ -f "${SERVICE_FILE}" ] || return 1
    grep '^ExecStart=' "${SERVICE_FILE}" | head -n 1
}

get_current_port() {
    local exec_line
    exec_line=$(get_service_execstart) || return 1
    echo "$exec_line" | sed -n 's/.*-l [^:]*:\([0-9]\{1,5\}\).*/\1/p'
}

get_current_password() {
    local exec_line
    exec_line=$(get_service_execstart) || return 1
    echo "$exec_line" | sed -n 's/.*-p "\([^"]*\)".*/\1/p'
}

get_service_status_text() {
    if ! is_installed; then
        echo "未安装"
        return
    fi

    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        echo "运行中"
    else
        echo "未运行"
    fi
}

get_service_status_colored() {
    local status_text
    status_text=$(get_service_status_text)
    case "$status_text" in
        运行中) echo -e "${GREEN}${status_text}${NC}" ;;
        未安装) echo -e "${RED}${status_text}${NC}" ;;
        *) echo -e "${YELLOW}${status_text}${NC}" ;;
    esac
}

print_divider() {
    echo -e "${BLUE}--------------------------------------------------${NC}"
}

print_header() {
    clear 2>/dev/null || true
    echo -e "${CYAN}${BOLD}==================================================${NC}"
    echo -e "${CYAN}${BOLD}           AnyTLS 管理脚本（中文交互版）           ${NC}"
    echo -e "${CYAN}${BOLD}==================================================${NC}"
}

show_summary() {
    local install_text service_text current_port

    if is_installed; then
        install_text="${GREEN}已安装${NC}"
        current_port=$(get_current_port)
        [ -z "$current_port" ] && current_port="未知"
    else
        install_text="${RED}未安装${NC}"
        current_port="-"
    fi

    service_text=$(get_service_status_colored)

    echo -e "${BOLD}当前概览${NC}"
    echo -e "  安装状态：${install_text}"
    echo -e "  服务状态：${service_text}"
    echo -e "  当前端口：${YELLOW}${current_port}${NC}"
    print_divider
}

generate_random_port() {
    local port
    while true; do
        port=$(shuf -i ${PORT_MIN}-${PORT_MAX} -n 1 2>/dev/null || jot -r 1 ${PORT_MIN} ${PORT_MAX})
        if ! is_port_in_use "$port"; then
            echo "$port"
            return
        fi
    done
}

choose_port() {
    local choice custom_port random_port confirm

    >&2 echo
    >&2 echo -e "${BOLD}端口设置${NC}"
    >&2 echo "  1）使用默认端口 ${DEFAULT_PORT}"
    >&2 echo "  2）手动输入端口"
    >&2 echo "  3）随机生成可用端口"

    while true; do
        read -rp "请选择 [1-3，默认 1]：" choice >&2
        choice=${choice:-1}
        case "$choice" in
            1)
                if is_port_in_use "$DEFAULT_PORT"; then
                    warn "默认端口 ${DEFAULT_PORT} 已被占用，请确认是否继续使用"
                    read -rp "仍然使用默认端口吗？[y/N]：" confirm
                    case "$confirm" in
                        y|Y) echo "$DEFAULT_PORT"; return ;;
                        *) continue ;;
                    esac
                fi
                echo "$DEFAULT_PORT"
                return
                ;;
            2)
                while true; do
                    read -rp "请输入端口（${PORT_MIN}-${PORT_MAX}）：" custom_port
                    if ! is_valid_port "$custom_port"; then
                        warn "端口无效，请输入 ${PORT_MIN}-${PORT_MAX} 之间的数字"
                        continue
                    fi
                    if is_port_in_use "$custom_port"; then
                        warn "端口 ${custom_port} 已被占用，请更换其他端口"
                        continue
                    fi
                    echo "$custom_port"
                    return
                done
                ;;
            3)
                random_port=$(generate_random_port)
                info "已生成随机可用端口：${random_port}"
                echo "$random_port"
                return
                ;;
            *)
                warn "无效选项，请输入 1、2 或 3"
                ;;
        esac
    done
}

generate_password() {
    if command_exists uuidgen; then
        uuidgen | tr -d '-'
    else
        tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
    fi
}

show_menu() {
    print_header
    show_summary
    echo -e "${BOLD}功能菜单${NC}"
    echo "  1）安装 AnyTLS"
    echo "  2）升级 AnyTLS（保留配置）"
    echo "  3）查看当前配置"
    echo "  4）查看服务状态"
    echo "  5）重置监听端口"
    echo "  6）重置连接密码"
    echo "  7）卸载 AnyTLS"
    echo "  8）查看使用说明"
    echo "  0）退出脚本"
    print_divider
}

show_help() {
    print_header
    echo -e "${BOLD}命令行用法${NC}"
    echo "  sudo $0 install         安装 AnyTLS"
    echo "  sudo $0 upgrade         升级 AnyTLS（保留配置）"
    echo "  sudo $0 status          查看服务状态"
    echo "  sudo $0 config          查看当前配置"
    echo "  sudo $0 reset-port      重置监听端口"
    echo "  sudo $0 reset-password  重置连接密码"
    echo "  sudo $0 uninstall       卸载 AnyTLS"
    echo "  sudo $0                 打开交互菜单"
    print_divider
}

# ====================== 架构检测 ======================
detect_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) error "不支持的系统架构：$arch（当前仅支持 amd64 / arm64）" ;;
    esac
}

# ====================== 获取最新版本 ======================
get_latest_version() {
    curl -s https://api.github.com/repos/anytls/anytls-go/releases/latest \
        | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
}

# ====================== 下载 & 安装二进制 ======================
install_binary() {
    local version=$1
    local arch=$2
    local zip_name="anytls_${version#v}_linux_${arch}.zip"
    local download_url="https://github.com/anytls/anytls-go/releases/download/${version}/${zip_name}"
    local tmp_dir="/tmp/anytls_install_$$"

    mkdir -p "$tmp_dir" && cd "$tmp_dir"
    info "正在下载最新版本 ${version}（${arch}）..."
    curl -L -# -o "${zip_name}" "${download_url}"

    info "正在解压安装包..."
    unzip -o "${zip_name}" >/dev/null

    if [ -f "anytls-server" ]; then
        install -m 755 "anytls-server" "${INSTALL_BIN_DIR}/anytls-server"
        info "服务端程序已安装到 ${INSTALL_BIN_DIR}/anytls-server"
    else
        error "下载包中未找到 anytls-server 二进制文件"
    fi

    if [ -f "anytls-client" ]; then
        install -m 755 "anytls-client" "${INSTALL_BIN_DIR}/anytls-client"
    fi

    cd / && rm -rf "$tmp_dir"
}

# ====================== 创建 systemd 服务 ======================
create_service() {
    local listen_addr=$1
    local password=$2

    cat > "${SERVICE_FILE}" <<EOF2
[Unit]
Description=AnyTLS-Go Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${INSTALL_BIN_DIR}/anytls-server -l ${listen_addr} -p "${password}"
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF2

    systemctl daemon-reload
    systemctl enable --now "${SERVICE_NAME}.service" >/dev/null
    info "systemd 服务已创建并启动：${SERVICE_NAME}.service"
}

show_current_config() {
    if ! is_installed; then
        error "AnyTLS 尚未安装"
    fi

    local port password
    port=$(get_current_port)
    password=$(get_current_password)

    print_header
    echo -e "${BOLD}当前配置信息${NC}"
    echo -e "  监听地址：${YELLOW}0.0.0.0:${port}${NC}"
    echo -e "  连接密码：${YELLOW}${password}${NC}"
    echo -e "  连接示例：${YELLOW}anytls://${password}@你的IP:${port}${NC}"
    print_divider
}

show_service_status() {
    if ! is_installed; then
        error "AnyTLS 尚未安装"
    fi
    systemctl status "${SERVICE_NAME}.service" --no-pager
}

# ====================== 安装 ======================
do_install() {
    require_root

    if command_exists apt; then
        apt update -qq && apt install -y curl unzip
    elif command_exists dnf; then
        dnf install -y curl unzip
    elif command_exists yum; then
        yum install -y curl unzip
    fi

    local latest arch port password listen_addr
    latest=$(get_latest_version)
    arch=$(detect_arch)

    install_binary "$latest" "$arch"

    port=$(choose_port)
    password=$(generate_password)
    listen_addr="0.0.0.0:${port}"

    create_service "$listen_addr" "$password"

    print_header
    info "安装完成"
    echo -e "  监听地址：${YELLOW}${listen_addr}${NC}"
    echo -e "  随机密码：${YELLOW}${password}${NC}"
    echo -e "  客户端示例：${YELLOW}anytls://${password}@你的IP:${port}${NC}"
    warn "请立即保存上面的密码信息"
    print_divider
    echo "查看状态：systemctl status anytls"
    echo "查看日志：journalctl -u anytls -f"
}

# ====================== 升级（保留配置） ======================
do_upgrade() {
    require_root

    if ! is_installed; then
        error "AnyTLS 尚未安装，请先执行安装"
    fi

    local latest arch
    latest=$(get_latest_version)
    arch=$(detect_arch)

    info "即将升级到 ${latest}，当前端口和密码会保持不变"

    install_binary "$latest" "$arch"

    systemctl restart "${SERVICE_NAME}.service"
    info "升级完成，服务已自动重启"
}

reset_port() {
    require_root

    if ! is_installed; then
        error "AnyTLS 尚未安装"
    fi

    local current_password new_port listen_addr
    current_password=$(get_current_password)
    new_port=$(choose_port)
    listen_addr="0.0.0.0:${new_port}"

    create_service "$listen_addr" "$current_password"
    systemctl restart "${SERVICE_NAME}.service"

    info "监听端口已更新为 ${new_port}"
    echo -e "${YELLOW}连接示例：anytls://${current_password}@你的IP:${new_port}${NC}"
}

reset_password() {
    require_root

    if ! is_installed; then
        error "AnyTLS 尚未安装"
    fi

    local current_port new_password listen_addr
    current_port=$(get_current_port)
    new_password=$(generate_password)
    listen_addr="0.0.0.0:${current_port}"

    create_service "$listen_addr" "$new_password"
    systemctl restart "${SERVICE_NAME}.service"

    info "连接密码已重置"
    echo -e "${YELLOW}新密码：${new_password}${NC}"
    echo -e "${YELLOW}连接示例：anytls://${new_password}@你的IP:${current_port}${NC}"
}

uninstall_anytls() {
    require_root

    if ! is_installed; then
        error "AnyTLS 尚未安装"
    fi

    read -rp "确认要卸载 AnyTLS 吗？这会删除服务和二进制文件 [y/N]：" confirm
    case "$confirm" in
        y|Y)
            ;;
        *)
            info "已取消卸载操作"
            return
            ;;
    esac

    systemctl disable --now "${SERVICE_NAME}.service" >/dev/null 2>&1 || true
    rm -f "${SERVICE_FILE}"
    rm -f "${INSTALL_BIN_DIR}/anytls-server" "${INSTALL_BIN_DIR}/anytls-client"
    systemctl daemon-reload

    info "AnyTLS 已成功卸载"
}

pause_if_needed() {
    [ -t 0 ] || return
    read -rp "按回车键返回菜单..." _
}

interactive_menu() {
    local choice
    while true; do
        show_menu
        read -rp "请输入菜单编号 [0-8]：" choice
        case "$choice" in
            1) do_install || true; pause_if_needed ;;
            2) do_upgrade || true; pause_if_needed ;;
            3) show_current_config || true; pause_if_needed ;;
            4) show_service_status || true; pause_if_needed ;;
            5) reset_port || true; pause_if_needed ;;
            6) reset_password || true; pause_if_needed ;;
            7) uninstall_anytls || true; pause_if_needed ;;
            8) show_help || true; pause_if_needed ;;
            0)
                info "已退出脚本"
                break
                ;;
            *)
                warn "无效选项，请重新输入正确的菜单编号"
                pause_if_needed
                ;;
        esac
    done
}

# ====================== 主程序 ======================
case "$1" in
    install)
        do_install
        ;;
    upgrade|update)
        do_upgrade
        ;;
    status)
        show_service_status
        ;;
    config)
        show_current_config
        ;;
    reset-port)
        reset_port
        ;;
    reset-password)
        reset_password
        ;;
    uninstall|remove)
        uninstall_anytls
        ;;
    "")
        interactive_menu
        ;;
    *)
        show_help
        ;;
esac
