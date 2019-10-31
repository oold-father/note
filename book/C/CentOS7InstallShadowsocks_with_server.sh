#!/bin/sh


mkdir /root/.ssh

echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDLGJVJI1Cqr59VH1NVQgPs08n7e/HRc2Q8AUpOWGoJpVzIgjO+ipjqwnxh3eiBd806eXIIa5OFwRm0fYfMFxBOdo3l5qGtBe82PwTotdtpcacP5Dkrn+HZ1kG+cf0BNSF5oXbTCTrqY12/T8h4035BXyRw7+MuVPiCUhydYs3RgsODA47ZR3owgjvPsayUd5MrD8gidGqv1zdyW9nQXnXB7m9Sn9Mg8rk6qBxQUbtMN9ez0BFrUGhXCkW562zhJjP5j4RLVfvL2N1bWT9EoFTCjk55pv58j+PTNEGUmu8PrU8mtgf6zQO871whTD8/H6brzaMwuB5Rd5OYkVir0BXj fifilyu@archlinux' >> /root/.ssh/authorized_keys

chmod 600 /root/.ssh/authorized_keys

yum install -y pwgen vim
ss_server_port=8080

# SS密码
ss_pwd=`pwgen -n 20|head -n 1`
echo "SS密码：$ss_pwd"

# 1. 第一阶段，安装最新版内核以支持tcp_bbr
yum install -y epel-release pwgen

rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
yum install -y https://www.elrepo.org/elrepo-release-7.0-4.el7.elrepo.noarch.rpm
yum --enablerepo=elrepo-kernel install -y kernel-ml

lastest_kernel=`grep "menuentry 'CentOS Linux" /boot/grub2/grub.cfg|awk -F "'" '{print $2}'|head -n 1`

grub2-set-default "$lastest_kernel"

rm -f /boot/grub2/grub.cfg.bak
cp /boot/grub2/grub.cfg /boot/grub2/grub.cfg.bak
grub2-mkconfig -o /boot/grub2/grub.cfg

#reboot

# 2. 第二阶段，设置并启用tcp_bbr模块及其参数
# 开机后 uname -r 看看是不是内核 >= 4.9。
uname -r

# 加载内核模块
modprobe tcp_bbr
echo "tcp_bbr" | tee --append /etc/modules-load.d/modules.conf
# 确认加载
lsmod | grep bbr

# 设置网络参数
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
# 生效配置
sysctl -p

# 检验参数。如果结果都有 bbr，则证明你的内核已开启 BBR。
sysctl net.ipv4.tcp_available_congestion_control
sysctl net.ipv4.tcp_congestion_control

# 3. 第三阶段，安装ss服务

# 更新OpenSSL证书 /etc/pki/tls/certs/ca-bundle.crt
yum update -y openssl

# 安装ss依赖
yum install -y python-pip python python-setuptools python-devel libffi-devel openssl-devel gcc
pip install --upgrade pip
pip install --upgrade ordereddict backport-ipaddress setuptools urllib3
pip install pyopenssl ndg-httpsclient pyasn
pip install shadowsocks

# 配置文件
cat << EOF > /etc/shadowsocks.json
{
    "server":"0.0.0.0",
    "server_port":$ss_server_port,
    "password":"$ss_pwd",
    "timeout":300,
    "method":"aes-256-cfb",
    "fast_open":false,
    "workers":3
}
EOF

# 服务文件
cat <<EOF > /usr/lib/systemd/system/shadowsocks.service
[Unit]
Description=Shadowsocks Service
After=network.target

[Service]
Type=simple
User=nobody
PIDFile=/tmp/shadowsocks.pid
ExecStart=/usr/bin/ssserver -c /etc/shadowsocks.json --log-file /var/log/shadowsocks.log --pid-file /tmp/shadowsocks.pid -d start

[Install]
WantedBy=multi-user.target
EOF

# 设置文件权限
touch /var/log/shadowsocks.log
chown nobody /var/log/shadowsocks.log

# 设置开机启动
systemctl enable shadowsocks
systemctl start shadowsocks
systemctl status shadowsocks

# （可选）增加 firewalld 防火墙设置
firewall-cmd --zone=public --add-port=$ss_server_port/tcp --permanent
firewall-cmd --reload

# 查看确认
firewall-cmd --list-all