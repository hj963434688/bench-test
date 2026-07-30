#!/bin/bash

output_file="env_info.txt"

# 帮助信息
usage() {
    echo "Usage: $0 [-o output_file] [-h]"
    echo "  -o  Specify the output file (default: env_info.txt)"
    echo "  -h  Display this help message"
    exit 1
}

while getopts ":o:h" opt; do
    case ${opt} in
        o ) output_file=$OPTARG ;;
        h ) usage ;;
        \? ) echo "Invalid option: -$OPTARG" 1>&2; usage ;;
        : ) echo "Option -$OPTARG requires an argument" 1>&2; usage ;;
    esac
done

output_path=$(dirname "$output_file")
mkdir -p "$output_path"

# 重定向输出（终端和文件）
exec > >(tee -a "$output_file") 2>&1

echo "======================= CPU ==========================="
echo -n "CPU Cores: "
cat /proc/cpuinfo | grep "physical id" | sort | uniq | wc -l | xargs
echo -n "Model: "
cat /proc/cpuinfo | grep "model name" | uniq | cut -f2 -d: | sed 's/^ //'
lscpu | grep "CPU MHz"

echo "======================= Memory ========================="
# 保持原脚本的一行式输出（简洁）
echo -n "$(dmidecode -t memory | grep Speed | grep "Configured" | grep -v Unkn | wc -l) * "
echo -n "$(dmidecode -t memory | grep -i "manu\|part" | grep -v "Unknown\|DIMM" | sort | uniq | awk -F : '{print $2}' | xargs) "
echo -n "$(dmidecode -t memory | grep Size | grep -v Ins | grep -v "None\|Vola" | uniq | awk -F: '{print $2}' | xargs | sed 's/[[:space:]]//g') "
echo -n "$(dmidecode -t memory | grep Rank | sort | grep -v Unk | uniq | awk '{print $NF}')R "
echo "$(dmidecode -t memory | grep Speed | grep -v "Unk\|Con" | uniq | awk -F" " '{print $2}')MT/s running on $(dmidecode -t memory | grep Speed | grep Con | grep -v Un | uniq | awk -F' ' '{print $4}')MT/s"

echo "======================= Disks =========================="
num=$(lsblk -o model | sort | grep -vi model | uniq | sed /^[[:space:]]*$/d | wc -l)
for i in $(seq 1 $num); do
    name=$(lsblk -o model | sort | grep -vi model | uniq | sed /^[[:space:]]*$/d | sed -n "${i}p")
    echo -n "$(lsblk -o model | sort | grep -vi model | sed /^[[:space:]]*$/d | grep "$name" | wc -l) * "
    echo -n "$name "
    echo -n "$(lsblk -o model,size | grep "$name" | uniq | awk -F"$name" '{print $2}') "
    dev_n=$(lsblk -o name,model | grep "$name" | awk '{print $1}' | xargs | awk '{print $1}')
    echo "  FW: $(smartctl -i /dev/$dev_n 2>/dev/null | grep "^Firm" | awk -F: '{print $2}' | uniq | xargs)"
done

echo "======================= Base Info ======================"
name=$(ipmitool fru 2>/dev/null | grep "Name" | awk -F: '{print $2}' | sed 's/^ *//' | uniq)
echo "Name: $name"
echo "BIOS: $(dmidecode -s bios-version)"
bmc_ver=$(ipmitool mc info 2>/dev/null | grep "Firmware Revision" | awk -F: '{print $2}' | xargs)
bmc_ip=$(ipmitool lan print 1 2>/dev/null | grep 'IP A' | tail -n1 | awk '{print $4}')
echo "BMC: $bmc_ver  (IP: $bmc_ip)"
board=$(dmidecode -t 2 | grep 'Product\|Serial' | awk -F: '{print $2}' | xargs | paste -d' ' -s)
echo "Board: $board"
serial=$(dmidecode -t 1 | grep Serial | awk '{print $3}')
echo "Serial Number: $serial"
echo "Clock Source: $(cat /sys/devices/system/clocksource/clocksource0/current_clocksource)"
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -f2 -d\") - $(cat /etc/redhat-release 2>/dev/null)"
echo "Kernel: $(uname -r)"

echo "======================= hy-smi Info ====================="
if command -v hy-smi >/dev/null 2>&1; then
    echo "--- hy-smi ---"
    hy-smi
    hy-smi --showproductname
    hy-smi --showdriverversion
    hy-smi --showdriverversion
    hy-smi --showtopo
    hy-smi -v
    hy-smi -s
else
    echo "hy-smi command not found."
fi

echo "========================================================"
echo "Environment info saved to $output_file"