#!/bin/bash
set -e

# 1. Контейнер
docker build -t my-script .
docker rm -f my-app 2>/dev/null || true
docker run -d -p 8080:8080 --name my-app my-script

# 2. RAID/LVM на loop-устройствах (номера ловим автоматически, не хардкодим)
sudo apt-get update -y >/dev/null 2>&1
sudo apt-get install -y mdadm lvm2 >/dev/null 2>&1
mkdir -p /tmp/raid-lab && cd /tmp/raid-lab
dd if=/dev/zero of=disk1.img bs=1M count=200 status=none
dd if=/dev/zero of=disk2.img bs=1M count=200 status=none
dd if=/dev/zero of=disk3.img bs=1M count=200 status=none
LOOP1=$(sudo losetup -fP --show disk1.img)
LOOP2=$(sudo losetup -fP --show disk2.img)
LOOP3=$(sudo losetup -fP --show disk3.img)

yes | sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 "$LOOP1" "$LOOP2"
sudo mkfs.ext4 -F /dev/md0
sudo mkdir -p /mnt/raid && sudo mount /dev/md0 /mnt/raid

yes | sudo pvcreate "$LOOP3"
sudo vgcreate vg_data "$LOOP3"
yes | sudo lvcreate -L 100M -n lv_logs vg_data
sudo mkfs.ext4 -F /dev/vg_data/lv_logs
sudo mkdir -p /mnt/logs && sudo mount /dev/vg_data/lv_logs /mnt/logs

# 3. nginx + TLS + systemd
sudo apt-get install -y nginx >/dev/null 2>&1
sudo tee /etc/nginx/sites-available/my-app > /dev/null <<'NGINX'
server {
    listen 80;
    server_name _;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl;
    server_name _;
    ssl_certificate     /etc/ssl/certs/my-app.crt;
    ssl_certificate_key /etc/ssl/private/my-app.key;
    location / {
        proxy_pass http://127.0.0.1:8080;
    }
}
NGINX
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/my-app.key -out /etc/ssl/certs/my-app.crt -subj "/CN=my-app.local"
sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/my-app /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

sudo tee /etc/systemd/system/my-app.service > /dev/null <<'UNIT'
[Unit]
Description=my-app service
After=docker.service
Requires=docker.service

[Service]
ExecStart=docker start -a my-app
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
docker rm -f my-app
docker create -p 8080:8080 --name my-app my-script
sudo systemctl daemon-reload
sudo systemctl enable my-app
sudo systemctl start my-app

echo "=== bootstrap.sh done ==="
sudo nginx -t
curl -kI https://127.0.0.1/
sudo systemctl status my-app --no-pager
cat /proc/mdstat
df -h /mnt/raid /mnt/logs
