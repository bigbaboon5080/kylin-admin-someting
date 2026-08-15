#!/bin/bash
#======================================================================
# 网卡信息自动检测脚本
# 适用系统: 麒麟操作系统桌面版 (Kylin Desktop) 及其它 GNU/Linux
# 功能: 逐个检测并列出每块【物理网卡】的 4 项关键信息:
#         1. IP 地址
#         2. MAC 地址
#         3. 子网掩码
#         4. 默认网关
#       自动过滤回环接口(lo)及虚拟/隧道接口(如 sit0、ip6tnl0、docker0 等)
# 依赖: iproute2 (命令: ip)，麒麟桌面版默认已安装
# 用法: bash detect_network.sh   (或 chmod +x detect_network.sh 后 ./detect_network.sh)
#======================================================================

set -u

# 检查 ip 命令是否存在
if ! command -v ip >/dev/null 2>&1; then
    echo "[错误] 未找到 ip 命令，请先安装 iproute2 软件包。"
    echo "       麒麟桌面版可执行: sudo apt install iproute2"
    exit 1
fi

#----------------------------------------------------------------------
# 函数: 将 CIDR 前缀长度转换为点分十进制子网掩码
#   参数: $1 - 前缀长度 (0-32)
#   输出: 子网掩码, 例如 255.255.255.0
#----------------------------------------------------------------------
cidr_to_mask() {
    local prefix="$1"
    local mask="" octet i
    for i in 1 2 3 4; do
        if [ "$prefix" -ge 8 ]; then
            octet=255
            prefix=$((prefix - 8))
        elif [ "$prefix" -gt 0 ]; then
            octet=$((256 - (1 << (8 - prefix))))
            prefix=0
        else
            octet=0
        fi
        mask="${mask}${octet}"
        [ "$i" -lt 4 ] && mask="${mask}."
    done
    echo "$mask"
}

#----------------------------------------------------------------------
# 获取物理网卡名称 (排除回环 lo 及虚拟/隧道接口, 如 sit0、ip6tnl0、
# docker0、veth*、tun*、tap* 等)
#   判断依据: 物理网卡在 /sys/class/net/<网卡>/device 下存在设备节点,
#             虚拟接口则没有该节点
#----------------------------------------------------------------------
get_interfaces() {
    local iface
    for iface in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -v '^lo$'); do
        if [ -e "/sys/class/net/$iface/device" ]; then
            echo "$iface"
        fi
    done
}

#----------------------------------------------------------------------
# 获取指定网卡的 IP 地址 (取第一个 IPv4 地址)
#----------------------------------------------------------------------
get_ip() {
    ip -o -4 addr show dev "$1" 2>/dev/null | awk '{print $4}' | head -n 1 | cut -d'/' -f1
}

#----------------------------------------------------------------------
# 获取指定网卡的 CIDR 前缀长度
#----------------------------------------------------------------------
get_prefix() {
    ip -o -4 addr show dev "$1" 2>/dev/null | awk '{print $4}' | head -n 1 | cut -d'/' -f2
}

#----------------------------------------------------------------------
# 获取指定网卡的 MAC 地址
#----------------------------------------------------------------------
get_mac() {
    ip -o link show dev "$1" 2>/dev/null | awk '{print $17}'
}

#----------------------------------------------------------------------
# 获取指定网卡的默认网关
#----------------------------------------------------------------------
get_gateway() {
    # 优先: 显式指定该网卡的默认路由
    local gw
    gw=$(ip route show default dev "$1" 2>/dev/null | awk '{print $3; exit}')
    if [ -z "$gw" ]; then
        # 其次: 从全局默认路由中匹配该网卡
        gw=$(ip route show default 2>/dev/null | grep "dev $1" | awk '{print $3; exit}')
    fi
    echo "$gw"
}

#======================================================================
# 主程序
#======================================================================
echo "================================================================"
echo "  网卡信息检测结果"
echo "  系统    : $(uname -s) $(uname -r)"
echo "  检测时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================================"
echo ""

found=0
for iface in $(get_interfaces); do
    found=1

    ip_addr=$(get_ip "$iface")
    prefix=$(get_prefix "$iface")
    mac=$(get_mac "$iface")
    gw=$(get_gateway "$iface")

    # 子网掩码: 根据前缀长度转换; 未配置地址时显示 --
    if [ -n "$prefix" ]; then
        mask=$(cidr_to_mask "$prefix")
    else
        mask="--"
    fi

    # 信息缺失时用占位符标识
    [ -z "$ip_addr" ] && ip_addr="-- (未配置)"
    [ -z "$mac" ] && mac="--"
    [ -z "$gw" ] && gw="-- (无默认网关)"

    echo "--------------------------------------------------------------"
    echo "  网卡名称 : $iface"
    echo "  IP 地址  : $ip_addr"
    echo "  MAC 地址 : $mac"
    echo "  子网掩码 : $mask"
    echo "  默认网关 : $gw"
    echo ""
done

if [ "$found" -eq 0 ]; then
    echo "未检测到任何网卡设备。"
fi

echo "================================================================"
exit 0
