#!/usr/bin/env bash
# MTProto 代理 — 交互工具箱（依赖 Docker / docker compose）

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/guthy325630/mp/main}"
INSTALL_DIR="${INSTALL_DIR:-$(pwd)/mtproxy-data}"
# 科技lion 官方一键：bash <(curl -sL kejilion.sh) — curl 需完整 URL，见 https://github.com/kejilion/sh
KEJILION_SCRIPT_URL="${KEJILION_SCRIPT_URL:-https://kejilion.sh}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[信息]${NC} $*"; }
warn()  { echo -e "${YELLOW}[警告]${NC} $*"; }
err()   { echo -e "${RED}[错误]${NC} $*"; }

resolve_script_dir() {
	local s="${BASH_SOURCE[0]:-}"
	if [[ -z "$s" ]] || [[ "$s" == "-" ]]; then
		echo ""
		return
	fi
	if [[ "$s" != */* ]]; then
		echo "$(pwd)"
		return
	fi
	cd "$(dirname "$s")" && pwd
}

# 与 install.sh 同目录时优先用本地脚本，否则从 GitHub Raw 拉取
init_repo_source() {
	REPO_LOCAL=""
	local sd
	sd="$(resolve_script_dir)"
	if [[ -n "$sd" ]] && [[ -f "${sd}/install.sh" ]]; then
		REPO_LOCAL="$sd"
	fi
}

run_install_script() {
	ensure_install_abs
	export INSTALL_DIR REPO_RAW
	if [[ -n "$REPO_LOCAL" ]]; then
		bash "${REPO_LOCAL}/install.sh"
	else
		local tmp
		tmp="$(mktemp)" || { err "无法创建临时文件。"; return 1; }
		if ! curl -fsSL "${REPO_RAW}/install.sh" -o "$tmp"; then
			rm -f "$tmp"
			err "无法下载 install.sh：${REPO_RAW}/install.sh"
			return 1
		fi
		bash "$tmp"
		local ec=$?
		rm -f "$tmp"
		return "$ec"
	fi
}

run_uninstall_script() {
	local target="$1"
	if [[ -n "$REPO_LOCAL" ]]; then
		bash "${REPO_LOCAL}/uninstall.sh" -y "$target"
	else
		curl -fsSL "${REPO_RAW}/uninstall.sh" | bash -s -- -y "$target"
	fi
}

have_docker() {
	command -v docker &>/dev/null && docker info &>/dev/null 2>&1
}

ensure_install_abs() {
	if [[ "${INSTALL_DIR}" != /* ]]; then
		INSTALL_DIR="$(pwd)/${INSTALL_DIR}"
	fi
}

is_install_present() {
	ensure_install_abs
	[[ -d "$INSTALL_DIR" ]] && [[ -f "${INSTALL_DIR}/docker-compose.yml" ]] && [[ -f "${INSTALL_DIR}/telemt.toml" ]]
}

read_listen_port() {
	local f="${INSTALL_DIR}/docker-compose.yml"
	if [[ ! -f "$f" ]]; then
		echo "443"
		return
	fi
	local p
	p=$(grep -E '^\s*-\s*"[0-9]+:443"' "$f" 2>/dev/null | head -1 | sed -E 's/.*"([0-9]+):443".*/\1/')
	[[ -n "$p" ]] && echo "$p" || echo "443"
}

print_tg_link() {
	ensure_install_abs
	local SECRET TLS_DOMAIN DOMAIN_HEX LONG_SECRET SERVER_IP LINK LISTEN_PORT raw
	local secret_file="${INSTALL_DIR}/.secret"
	local toml="${INSTALL_DIR}/telemt.toml"

	if [[ ! -f "$secret_file" ]]; then
		err "未找到 ${secret_file}，请先完成安装。"
		return 1
	fi
	if [[ ! -f "$toml" ]]; then
		err "未找到 ${toml}。"
		return 1
	fi

	SECRET=$(tr -d '\n\r' <"$secret_file")
	[[ -z "$SECRET" ]] && { err "密钥为空。"; return 1; }

	TLS_DOMAIN=$(grep -E '^[[:space:]]*tls_domain[[:space:]]*=' "$toml" | head -1 | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/')
	[[ -z "$TLS_DOMAIN" ]] && { err "未在 telemt.toml 中找到 tls_domain。"; return 1; }

	DOMAIN_HEX=$(printf '%s' "$TLS_DOMAIN" | od -An -tx1 | tr -d ' \n')
	if [[ "$SECRET" =~ ^[0-9a-fA-F]{32}$ ]]; then
		LONG_SECRET="ee${SECRET}${DOMAIN_HEX}"
	else
		LONG_SECRET="$SECRET"
	fi

	LISTEN_PORT="$(read_listen_port)"

	SERVER_IP=""
	for url in https://ifconfig.me/ip https://icanhazip.com https://api.ipify.org https://checkip.amazonaws.com; do
		raw=$(curl -s --connect-timeout 3 "$url" 2>/dev/null | tr -d '\n\r')
		if [[ -n "$raw" ]] && [[ ! "$raw" =~ [[:space:]] ]] && [[ ! "$raw" =~ (error|timeout|upstream|reset|refused) ]] && [[ "$raw" =~ ^([0-9.]+|[0-9a-fA-F:]+)$ ]]; then
			SERVER_IP="$raw"
			break
		fi
	done
	if [[ -z "$SERVER_IP" ]]; then
		SERVER_IP="YOUR_SERVER_IP"
		warn "无法自动获取公网 IP，请把链接里的 YOUR_SERVER_IP 换成你的服务器 IP。"
	fi

	LINK="tg://proxy?server=${SERVER_IP}&port=${LISTEN_PORT}&secret=${LONG_SECRET}"
	echo ""
	echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "${GREEN}  Telegram 代理链接（Fake TLS）${NC}"
	echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo ""
	echo -e "  ${GREEN}${LINK}${NC}"
	echo ""
	echo "  请勿公开分享该链接。"
	echo ""
}

prompt_change_install_dir() {
	local input
	echo -n "当前安装目录: ${INSTALL_DIR}"
	echo ""
	echo -n "请输入新目录（回车保持默认）: "
	read -r input
	[[ -z "$input" ]] && return
	if [[ "${input}" != /* ]]; then
		INSTALL_DIR="$(pwd)/${input}"
	else
		INSTALL_DIR="$input"
	fi
	ensure_install_abs
	info "已设为: ${INSTALL_DIR}"
}

menu_install() {
	if ! have_docker; then
		warn "未检测到可用 Docker。安装流程会尝试安装 Docker（通常需要 root）。"
		echo -n "继续？[y/N] "
		read -r c
		[[ "${c,,}" != "y" && "${c,,}" != "yes" ]] && return
	fi
	run_install_script
}

menu_uninstall() {
	ensure_install_abs
	if ! is_install_present; then
		err "目录中未发现已安装的 MTProxy：${INSTALL_DIR}"
		return 1
	fi
	echo -e "${YELLOW}将停止容器并删除整个目录：${INSTALL_DIR}${NC}"
	echo -n "确认卸载？[y/N] "
	read -r c
	[[ "${c,,}" != "y" && "${c,,}" != "yes" ]] && { info "已取消。"; return; }
	if ! have_docker; then
		err "Docker 不可用，无法停止容器。"
		return 1
	fi
	run_uninstall_script "$INSTALL_DIR"
}

menu_compose() {
	local cmd="$1"
	ensure_install_abs
	if ! is_install_present; then
		err "请先安装，或检查安装目录：${INSTALL_DIR}"
		return 1
	fi
	if ! have_docker; then
		err "Docker 不可用。"
		return 1
	fi
	(
		cd "$INSTALL_DIR" || exit 1
		docker compose "$@"
	)
}

show_status() {
	menu_compose ps
}

show_logs_tail() {
	menu_compose logs --tail 80
}

show_logs_follow() {
	info "按 Ctrl+C 结束日志跟踪。"
	menu_compose logs -f
}

menu_kejilion() {
	echo -e "${YELLOW}「科技lion」为第三方 Linux 运维脚本（非本仓库维护），使用前请自行评估风险。${NC}"
	echo "  官方仓库: https://github.com/kejilion/sh"
	echo -n "是否继续？[y/N] "
	read -r c
	[[ "${c,,}" != "y" && "${c,,}" != "yes" ]] && { info "已取消。"; return; }
	if ! command -v curl &>/dev/null; then
		err "需要先安装 curl。"
		return 1
	fi
	info "执行等效命令: bash <(curl -sL ${KEJILION_SCRIPT_URL})"
	bash <(curl -sL "$KEJILION_SCRIPT_URL")
}

show_header() {
	clear 2>/dev/null || true
	echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "${CYAN}  MTProto 代理 — 交互工具箱${NC}"
	echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "  安装目录: ${GREEN}${INSTALL_DIR}${NC}"
	if [[ -n "$REPO_LOCAL" ]]; then
		echo -e "  脚本来源: ${GREEN}本地 ${REPO_LOCAL}${NC}"
	else
		echo -e "  远程模板: ${GREEN}${REPO_RAW}${NC}"
	fi
	echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo ""
}

main_loop() {
	init_repo_source
	while true; do
		ensure_install_abs
		show_header
		echo "  1) 安装 / 配置并启动（一键安装）"
		echo "  2) 卸载（停止并删除安装目录）"
		echo "  3) 查看容器状态"
		echo "  4) 查看最近日志（末尾 80 行）"
		echo "  5) 实时跟踪日志"
		echo "  6) 停止服务"
		echo "  7) 启动服务"
		echo "  8) 重启服务"
		echo "  9) 显示 Telegram 代理链接"
		echo " 10) 修改安装目录（本会话）"
		echo " 11) 科技lion工具箱（第三方运维脚本）"
		echo "  0) 退出"
		echo ""
		echo -n "请选择 [0-11]: "
		read -r choice
		case "$choice" in
			1) menu_install ;;
			2) menu_uninstall ;;
			3) show_status || true ;;
			4) show_logs_tail || true ;;
			5) show_logs_follow || true ;;
			6) menu_compose down || true ;;
			7) menu_compose up -d || true ;;
			8) menu_compose restart || true ;;
			9) print_tg_link || true ;;
			10) prompt_change_install_dir ;;
			11) menu_kejilion || true ;;
			0)
				info "再见。"
				exit 0
				;;
			"")
				warn "请输入数字选项。"
				;;
			*)
				warn "无效选项，请重新输入。"
				;;
		esac
		echo ""
		echo -n "按 Enter 继续..."
		read -r _
	done
}

main_loop
