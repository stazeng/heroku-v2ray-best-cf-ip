#!/bin/bash

# 测速阈值，单位 Mb/s，超过阈值，则不会重新测速
# 20201121 最近速度很慢，在 0-8 Mb/s
base_speed=5

# 初始化，否则第一次运行(未生成 ip.txt)会报错
current_speed=0

fping_count=30

start_seconds=$(date +%s)

echo "$(date) 开始运行"

# 等待 NAS 开机完成，否则测速不准
sleep 10

# 通过两次测速判断 current ip 是否满足要求
# [ -s $file ] 判断文件不为空
if [ -s ip.txt ]; then
    echo "测速目前 IP 的速度"
    ip=$(cat ip.txt)
    speed=$(($(curl --resolve speed.cloudflare.com:443:$ip https://speed.cloudflare.com/__down?bytes=1000000000 -o /dev/null -s -w '%{speed_download}\n' --connect-timeout 5 --max-time 15 | sed "s/.000//") / 1024 / 1024 * 8))
    if [ $speed -gt $base_speed ]; then
        echo "目前 IP $ip 速度 ${speed}Mb/s 大于 ${base_speed}Mb/s"
        echo "$(date) 结束运行"
        exit 0
    else
        higher_speed=$speed
        speed=$(($(curl --resolve apple.freecdn.workers.dev:443:$ip https://apple.freecdn.workers.dev/105/media/us/iphone-11-pro/2019/3bd902e4-0752-4ac1-95f8-6225c32aec6d/films/product/iphone-11-pro-product-tpl-cc-us-2019_1280x720h.mp4 -o /dev/null -s -w '%{speed_download}\n' --connect-timeout 5 --max-time 15 | sed "s/.000//") / 1024 / 1024 * 8))
        if [ $speed -gt $base_speed ]; then
            echo "目前 IP $ip 速度 ${speed}Mb/s 大于 ${base_speed}Mb/s"
            echo "$(date) 结束运行"
            exit 0
        fi
        if [ $speed -gt $higher_speed ]; then higher_speed=$speed; fi
    fi
    current_ip=$ip
    current_speed=$higher_speed
    echo "目前 IP $current_ip 速度 ${current_speed}Mb/s"
fi

echo "目前 IP 不满足要求，寻找新 IP"

rm -rf /tmp/*

echo "ip-core.txt to ip-random.txt"
for ip in $(cat ip-core.txt); do
    r=$((($RANDOM * 2 + 1) % 255))
    echo $ip | sed "s/.$/$r/" >>/tmp/ip-random.txt
done

echo "ip-random.txt to ip-100.txt"
# 2>/dev/null 不显示错误提示
fping -f /tmp/ip-random.txt -c $fping_count -i 0 2>/dev/null | grep "\[$(($fping_count - 1))\]" | sort -n -k 10 | head -100 >/tmp/ip-100.txt

# 在运行过程中，出现过路由器故障，导致 fping 异常，ip-100.txt 是空文件，下面的判断语句用于捕捉这个异常
# [ ! -s $file ] 判断文件为空
if [ ! -s /tmp/ip-100.txt ]; then
    echo "fping ip-100 error!"
    exit 1
fi

echo "ip-100.txt to ip-3.txt"
for ip in $(cat /tmp/ip-100.txt | awk '{print $1}'); do
    curl --resolve speed.cloudflare.com:443:$ip https://speed.cloudflare.com/__down?bytes=1000000000 -o /tmp/$ip -s --connect-timeout 2 --max-time 10 &
    sleep 0.5
done
sleep 10
ls -S /tmp | head -3 >/tmp/ip-3.txt

# 对最快的三个 ip 按两种方式独立测速，准确性较高
echo "ip-3.txt to ip-6.txt"
for ip in $(cat /tmp/ip-3.txt); do
    curl --resolve speed.cloudflare.com:443:$ip https://speed.cloudflare.com/__down?bytes=1000000000 -o /dev/null -s -w '%{speed_download}\n' --connect-timeout 5 --max-time 15 | sed "s/.000/\t$ip/" >>/tmp/ip-6.txt
    sleep 0.5
    curl --resolve apple.freecdn.workers.dev:443:$ip https://apple.freecdn.workers.dev/105/media/us/iphone-11-pro/2019/3bd902e4-0752-4ac1-95f8-6225c32aec6d/films/product/iphone-11-pro-product-tpl-cc-us-2019_1280x720h.mp4 -o /dev/null -s -w '%{speed_download}\n' --connect-timeout 5 --max-time 15 | sed "s/.000/\t$ip/" >>/tmp/ip-6.txt
    sleep 0.5
done

echo "ip-6.txt to ip.txt"
last=$(cat /tmp/ip-6.txt | sort -r -n -k 1 | head -1)
last_ip=$(echo $last | awk '{print $2}')
last_speed=$(($(echo $last | awk '{print $1}') / 1024 / 1024 * 8))
# last_speed vs current_speed
if [ $current_speed -gt $last_speed ]; then
    last_speed=$current_speed
    last_ip=$current_ip
fi
echo $last_ip >ip.txt

end_seconds=$(date +%s)

echo "$last_ip 满足要求，速度是 ${last_speed}Mb/s，耗时 $(($end_seconds - $start_seconds)) 秒！"

echo "修改 v2ray 配置文件中的 IP"
sed -i "s/\(\"address\":\"\)\(.*\)\(\",\)/\1${last_ip}\3/" /root/v2ray/config.json

# $DOCKERNAME : ENV 变量
echo "重启容器"
docker restart $DOCKERNAME

rm -rf /tmp/*

echo "$(date) 结束运行"
