#!/bin/bash
#======================================================================
# 麒麟系统桌面版 开关机记录查询脚本
# 适用系统: 麒麟桌面版 (Kylin Desktop) / 其他基于 systemd 的 GNU/Linux
# 功能: 详细列出每一次的 开机时间 和 关机时间
#
# 数据源(按优先级):
#   首选 - 系统记账文件 /var/log/wtmp (last -xF reboot)
#           wtmp 按本地时间记账, 直接给出每次开机的 开机时间 与 关机时间,
#           可靠性高, 不受系统时钟早期偏移影响(如 RTC 本地时间模式)
#   备用 - systemd 日志 (journalctl --list-boots --utc)
#           journal 内部以 UTC 存储, 脚本用 date 自行转换为本地时间显示
#
# 用法: bash boot_shutdown_records.sh
#   提示: 若权限不足导致 wtmp/journal 无法读取, 可加 sudo 运行:
#         sudo bash boot_shutdown_records.sh
#======================================================================
set -u

#----------------------------------------------------------------------
# 函数: 判断当前系统是否基于 systemd
#----------------------------------------------------------------------
is_systemd() {
    [ -d /run/systemd/system ] && return 0
    return 1
}

#----------------------------------------------------------------------
# 函数: 获取系统本地时区标识 (如 Asia/Shanghai)
#   优先级: /etc/timezone -> /etc/localtime 软链接 -> timedatectl
#   失败时输出空字符串
#----------------------------------------------------------------------
get_local_tz() {
    if [ -f /etc/timezone ]; then
        cat /etc/timezone
        return 0
    fi
    if [ -L /etc/localtime ]; then
        readlink /etc/localtime | sed 's|^.*/zoneinfo/||'
        return 0
    fi
    if command -v timedatectl >/dev/null 2>&1; then
        timedatectl show -p Timezone --value 2>/dev/null
        return 0
    fi
    echo ""
    return 0
}

#----------------------------------------------------------------------
# 函数: 将 UTC 时间字符串转换为本地时间
#   参数: $1 - UTC 时间 "YYYY-MM-DD HH:MM:SS"
#   输出: 本地时间 "YYYY-MM-DD HH:MM:SS"
#   说明: 使用系统默认本地时区(/etc/localtime)转换,
#         与 uptime -s、date 的显示保持一致, 自动适配东八区等
#----------------------------------------------------------------------
utc_to_local() {
    local utc_dt="$1"
    date -d "${utc_dt} UTC" '+%Y-%m-%d %H:%M:%S' 2>/dev/null
}

#----------------------------------------------------------------------
# 函数: 月份英文名转数字 (Jan -> 01)
#----------------------------------------------------------------------
month2num() {
    case "$1" in
        Jan) echo 01 ;; Feb) echo 02 ;; Mar) echo 03 ;; Apr) echo 04 ;;
        May) echo 05 ;; Jun) echo 06 ;; Jul) echo 07 ;; Aug) echo 08 ;;
        Sep) echo 09 ;; Oct) echo 10 ;; Nov) echo 11 ;; Dec) echo 12 ;;
        *)   echo "00" ;;
    esac
}

#----------------------------------------------------------------------
# 函数: 将 last 输出的 "Aug 15 08:17:06 2026" 转为 "2026-08-15 08:17:06"
#   参数: $1=星期 $2=月份 $3=日 $4=时刻 $5=年
#----------------------------------------------------------------------
fmt_last_time() {
    local mon
    mon=$(month2num "$2")
    printf '%s-%s-%s %s\n' "$5" "$mon" "$3" "$4"
}

#----------------------------------------------------------------------
# 函数: 从系统记账文件 /var/log/wtmp (last) 获取开关机记录
#   成功时逐行输出 "开机时间|关机时间|状态"(关机时间空=仍在运行)
#   返回 0 表示有记录, 1 表示无记录
#----------------------------------------------------------------------
collect_from_last() {
    local found=0 line boot_tm shut_tm
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        # 只处理 reboot 开头的行, 跳过 wtmp begins 等
        case "$line" in
            reboot\ *) ;;
            *) continue ;;
        esac
        # 按空白分词: reboot system boot 内核 星期 月 日 时 年 [still| - 星期2 月2 日2 时2 年2]
        # 注意: bash 中超过 9 的位置参数必须用 ${10} 形式, 不能写 $10
        set -- $line
        boot_tm=$(fmt_last_time "$5" "$6" "$7" "$8" "$9")
        if [ "${10}" = "still" ]; then
            echo "${boot_tm}||正在运行"
        else
            shut_tm=$(fmt_last_time "${11}" "${12}" "${13}" "${14}" "${15}")
            echo "${boot_tm}|${shut_tm}|正常关机"
        fi
        found=1
    done < <(last -xF reboot 2>/dev/null)
    return $((1 - found))
}

#----------------------------------------------------------------------
# 函数: 输出单次开关机记录(两行式: 开机一行, 关机缩进对齐一行)
#   参数: $1=序号 $2=开机时间(YYYY-MM-DD HH:MM:SS) $3=关机时间
#         关机时间为空=仍在运行
#         同日只显示一次日期; 跨天显示两个日期并给出提示
#----------------------------------------------------------------------
print_record() {
    local seq="$1" boot_tm="$2" shut_tm="$3"
    local shut_disp hint="" hdr indent

    if [ -z "$shut_tm" ]; then
        # 仍在运行
        shut_disp="(尚未关机 / 正在运行)"
    elif [ "${boot_tm%% *}" = "${shut_tm%% *}" ]; then
        # 同日: 关机只显示时刻, 不重复日期
        shut_disp="${shut_tm##* }"
    else
        # 跨天: 关机显示完整日期时间, 并提示
        shut_disp="$shut_tm"
        hint="1"
    fi

    # 头部与缩进: 让"关机"标签缩进到开机时间起始列偏右(头部长度+6),
    # 并与关机值之间留出固定间隔, 对齐参考样式
    hdr="  第 ${seq} 次开关机记录 : "
    indent=$(printf '%*s' $(( ${#hdr} + 6 )) "")
    gap="            "   # 12 个空格间隔

    echo "--------------------------------------------------------------"
    echo "${hdr}开机 ${boot_tm}"
    echo "${indent}关机${gap}${shut_disp}"
    if [ -n "$hint" ]; then
        echo "  ※ 提示: 本次开机与关机不在同一天, 开机于 ${boot_tm%% *}, 关机于 ${shut_tm%% *}, 请核对"
    fi
    echo ""
}

#======================================================================
# 主程序
#======================================================================
# 检测系统本地时区, 用于强制按本地时间显示(避免 UTC)
LOCAL_TZ=$(get_local_tz)

echo "================================================================"
echo "  麒麟系统 开关机记录"
echo "  主机名  : $(hostname)"
echo "  系统    : $(uname -s) $(uname -r)"
echo "  查询时间: $(date '+%Y-%m-%d %H:%M:%S') $(date +%Z)"
[ -n "$LOCAL_TZ" ] && echo "  时区    : ${LOCAL_TZ}"
echo "================================================================"
echo ""

total=0

#------------------ 数据源 1: last 记账文件 (首选) ----------------------
if command -v last >/dev/null 2>&1; then
    records=$(collect_from_last)
    if [ -n "$records" ]; then
        echo "◆ 数据源: 系统记账文件 /var/log/wtmp (last -xF reboot)"
        echo ""

        seq=0
        while IFS='|' read -r boot_tm shut_tm st; do
            seq=$((seq + 1))
            total=$((total + 1))
            print_record "$seq" "$boot_tm" "$shut_tm"
        done <<< "$records"
    fi
fi

#------------------ 数据源 2: systemd journal (备用) --------------------
if [ "$total" -eq 0 ] && is_systemd && command -v journalctl >/dev/null 2>&1; then
    # --utc 强制 journal 统一输出 UTC 时间, 再在循环内用 date 转换为本地时间
    mapfile -t boots < <(journalctl --list-boots --utc 2>/dev/null)

    if [ "${#boots[@]}" -gt 0 ]; then
        echo "◆ 数据源: systemd 日志 (journalctl --list-boots --utc)"
        echo ""
        echo "  注: 若系统 RTC 配置为本地时间(rtc-in-local), journal 记录的"
        echo "      开机时间可能存在时区偏差, 此时请以 last 记账记录为准"
        echo ""

        seq=0
        for line in "${boots[@]}"; do
            # 只处理序号行(如 0, -1, -2 ...), 跳过其他内容
            [[ "$line" =~ ^[[:space:]]*-?[0-9]+[[:space:]] ]] || continue

            seq=$((seq + 1))
            total=$((total + 1))

            case "$line" in
                *—*)
                    left="${line%%—*}"     # 前半部分: 序号 启动ID 开始时间(UTC)
                    right="${line#*—}"     # 后半部分: 结束时间(UTC)
                    start_utc=$(echo "$left"  | awk '{print $4, $5}')
                    end_utc=$(echo "$right" | awk '{print $2, $3}')
                    start=$(utc_to_local "$start_utc")
                    end=$(utc_to_local "$end_utc")
                    ;;
                *)
                    start_utc=$(echo "$line" | awk '{print $4, $5}')
                    start=$(utc_to_local "$start_utc")
                    end=""                  # 空=仍在运行
                    ;;
            esac

            print_record "$seq" "$start" "$end"
        done
    fi
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
