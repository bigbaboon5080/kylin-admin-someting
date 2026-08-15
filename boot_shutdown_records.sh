#!/bin/bash
#======================================================================
# 麒麟系统桌面版 开关机记录查询脚本
# 适用系统: 麒麟桌面版 (Kylin Desktop) / 其他基于 systemd 的 GNU/Linux
# 功能: 详细列出每一次的 开机时间 和 关机时间
#
# 数据源(按优先级):
#   首选 - systemd 日志 (journalctl --list-boots)
#           开机时间 = 该次启动写入的第一条日志时间
#           关机时间 = 该次启动写入的最后一条日志时间(约等于关机时刻)
#   备用 - 系统记账文件 /var/log/wtmp (last 命令)
#
# 用法: bash boot_shutdown_records.sh
#   提示: 非 root 用户默认只能看到本用户可读的日志范围,
#         如需完整历史可加 sudo 运行: sudo bash boot_shutdown_records.sh
#======================================================================
set -u

#----------------------------------------------------------------------
# 函数: 判断当前系统是否基于 systemd
#----------------------------------------------------------------------
is_systemd() {
    [ -d /run/systemd/system ] && return 0
    return 1
}

#======================================================================
# 主程序
#======================================================================
echo "================================================================"
echo "  麒麟系统 开关机记录"
echo "  主机名  : $(hostname)"
echo "  系统    : $(uname -s) $(uname -r)"
echo "  查询时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================================"
echo ""

total=0

#------------------ 数据源 1: systemd journal --------------------------
if is_systemd && command -v journalctl >/dev/null 2>&1; then
    # 将每次启动记录读入数组 (mapfile 需 bash>=4)
    mapfile -t boots < <(journalctl --list-boots 2>/dev/null)

    if [ "${#boots[@]}" -gt 0 ]; then
        echo "◆ 数据源: systemd 日志 (journalctl --list-boots)"
        echo ""

        seq=0
        for line in "${boots[@]}"; do
            # 只处理序号行(如 0, -1, -2 ...), 跳过其他内容
            [[ "$line" =~ ^[[:space:]]*-?[0-9]+[[:space:]] ]] || continue

            seq=$((seq + 1))
            total=$((total + 1))

            # 判断该次启动是否有结束时间(用 — 分隔)
            case "$line" in
                *—*)
                    left="${line%%—*}"     # 前半部分: 序号 启动ID 开始时间
                    right="${line#*—}"     # 后半部分: 结束时间
                    # 开始时间取 left 的最后 3 个字段: 星期 日期 时刻
                    start=$(echo "$left"  | awk '{print $(NF-3), $(NF-2), $(NF-1)}')
                    # 结束时间取 right 的前 3 个字段: 星期 日期 时刻
                    end=$(echo "$right" | awk '{print $1, $2, $3}')
                    status="正常关机"
                    ;;
                *)
                    start=$(echo "$line" | awk '{print $(NF-3), $(NF-2), $(NF-1)}')
                    end="-- (尚未关机 / 正在运行)"
                    status="当前系统正在运行"
                    ;;
            esac

            echo "--------------------------------------------------------------"
            echo "  第 ${seq} 次开机记录"
            echo "  开机时间 : ${start}"
            echo "  关机时间 : ${end}"
            echo "  状态     : ${status}"
            echo ""
        done
    fi
fi

#------------------ 数据源 2: last 记账文件 (备用) ----------------------
if [ "$total" -eq 0 ] && command -v last >/dev/null 2>&1; then
    echo "◆ 数据源: 系统记账文件 /var/log/wtmp (last)"
    echo ""
    echo "  --- 开机 (reboot) 记录 ---"
    last -xF reboot 2>/dev/null | grep -vE '^(wtmp begins|[[:space:]]*$)' | head -20
    echo ""
    echo "  --- 关机 (shutdown) 记录 ---"
    last -xF shutdown 2>/dev/null | grep -vE '^(wtmp begins|[[:space:]]*$)' | head -20
    echo ""
fi

#------------------ 结果汇总 -------------------------------------------
if [ "$total" -eq 0 ]; then
    echo "未获取到开关机记录。"
    echo "可能原因: "
    echo "  1. 日志被清理或 journal 未持久化(/var/log/journal 不存在)"
    echo "  2. 当前用户权限不足, 可尝试: sudo bash $0"
    echo ""
else
    echo "================================================================"
    echo "  共查询到 ${total} 次开机记录"
fi

echo "================================================================"
exit 0
