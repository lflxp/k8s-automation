#!/bin/bash 
# 本脚本假设使用者已经装好了与K8S 相对应的docker
# 在所有 master 节点与 node 节点执行
# 此脚本需要与 nginx.conf kubernetes.repo nginx-proxy.service 三个文件在同一目录。
if [ `whoami` != 'root' ]
then
    echo 'you must run this script as root'
    exit 0
fi

if [ ! -f "./nginx.conf" ]; then
echo "missing nginx.conf file, exit"
exit 1
fi

if [ ! -f "./nginx-proxy.service" ]; then
echo "missing nginx-proxy.service file, exit"
exit 1
fi


if [ ! -f "./kubernetes.repo" ]; then
echo "missing kubernetes.repo file, exit"
exit 1
fi


# install neovim, this is optional
yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
yum install -y neovim python3-neovim


# close firewall
systemctl stop firewalld
systemctl disable firewalld

# 临时关闭 swap
swapoff -a
# 永久关闭  在/etc//fstab 中注释掉 "/dev/mapper/centos-swap swap"
sed -i 's/.*swap.*/#&/' /etc/fstab


# 关闭selinux
setenforce 0
# 永久关闭
sed -i "s/^SELINUX=enforcing/SELINUX=disabled/g" /etc/sysconfig/selinux
sed -i "s/^SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config
sed -i "s/^SELINUX=permissive/SELINUX=disabled/g" /etc/sysconfig/selinux
sed -i "s/^SELINUX=permissive/SELINUX=disabled/g" /etc/selinux/config

# 修改内核参数, 默认内核配置参数在/etc/sysctl.conf
touch /etc/sysctl.d/k8s.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/k8s.conf
echo "net.bridge.bridge-nf-call-iptables=1" >> /etc/sysctl.d/k8s.conf
echo "net.bridge.bridge-nf-call-ip6tables=1" >> /etc/sysctl.d/k8s.conf
echo "vm.swappiness=0" >> /etc/sysctl.d/k8s.conf
# 生效
sysctl -p /etc/sysctl.d/k8s.conf

# 调高 ulimit 最大文件打开数量，systemclt 管理服务文件的最大数量
touch /etc/security/limits.d/k8slimits.conf
echo "* soft nofile 655360" >> /etc/security/limits.d/k8slimits.conf
echo "* hard nofile 655360" >> /etc/security/limits.d/k8slimits.conf
echo "* soft nproc 655360" >> /etc/security/limits.d/k8slimits.conf
echo "* hard nproc 655360" >> /etc/security/limits.d/k8slimits.conf
echo "* soft memlock unlimited" >> /etc/security/limits.d/k8slimits.conf
echo "* hard memlock unlimited" >> /etc/security/limits.d/k8slimits.conf
echo "DefaultLimitNPROC=1024000" >> /etc/systemd/system.conf
echo "DefaultLimitNOFILE=1024000" >> /etc/systemd/system.conf
#此处是个坑， 如果此项没开，elasticsearch 没法集群部署，报bootstrap 错误 [1]: memory locking requested for elasticsearch process but memory is not locked
echo "DefaultLimitMEMLOCK=infinity" >> /etc/systemd/system.conf

# 加载ipvs 所需的内核模块
touch /etc/sysconfig/modules/ipvs.modules
echo '#!/bin/bash' >> /etc/sysconfig/modules/ipvs.modules
echo "modprobe -- ip_vs" >> /etc/sysconfig/modules/ipvs.modules
echo "modprobe -- ip_vs_rr" >> /etc/sysconfig/modules/ipvs.modules
echo "modprobe -- ip_vs_wrr" >> /etc/sysconfig/modules/ipvs.modules
echo "modprobe -- ip_vs_sh" >> /etc/sysconfig/modules/ipvs.modules
echo "modprobe -- nf_conntrack_ipv4" >> /etc/sysconfig/modules/ipvs.modules

# 授权
chmod 755 /etc/sysconfig/modules/ipvs.modules 

# 加载模块
bash /etc/sysconfig/modules/ipvs.modules

# 查看加载
lsmod | grep -e ip_vs -e nf_conntrack_ipv4

# 加载 glusterfs 所需的内核模块
touch /etc/sysconfig/modules/glusterfs.modules
echo '#!/bin/bash' >> /etc/sysconfig/modules/glusterfs.modules
echo "modprobe -- dm_snapshot" >> /etc/sysconfig/modules/glusterfs.modules
echo "modprobe -- dm_mirror" >> /etc/sysconfig/modules/glusterfs.modules
echo "modprobe -- dm_thin_pool" >> /etc/sysconfig/modules/glusterfs.modules
# 授权
chmod 755 /etc/sysconfig/modules/glusterfs.modules 

# 加载模块
bash /etc/sysconfig/modules/glusterfs.modules

lsmod | grep dm

mkdir - /etc/docker
touch /etc/docker/daemon.json
echo '{'>> /etc/docker/daemon.json
echo '  "log-opts": {' >> /etc/docker/daemon.json
echo '    "max-size": "100m"' >> /etc/docker/daemon.json
echo '  },' >> /etc/docker/daemon.json
echo '  "storage-driver": "overlay2",' >> /etc/docker/daemon.json
echo '  "exec-opts": ["native.cgroupdriver=systemd"],' >> /etc/docker/daemon.json
echo '  "dns":["114.114.114.114"],' >> /etc/docker/daemon.json
echo '  "dns-search":["default.svc.cluster.local","svc.cluster.local","localdomain"],' >> /etc/docker/daemon.json
echo '  "dns-opt":["ndots:2","timeout:2","attempts:2"],' >> /etc/docker/daemon.json
echo '  "registry-mirrors": [' >> /etc/docker/daemon.json
echo '    "https://fmu2ap2k.mirror.aliyuncs.com",' >> /etc/docker/daemon.json
echo '    "https://gcr-mirror.qiniu.com",' >> /etc/docker/daemon.json
echo '    "https://quay-mirror.qiniu.com",' >> /etc/docker/daemon.json
echo '    "https://docker.mirrors.ustc.edu.cn",' >> /etc/docker/daemon.json
echo '    "https://mirror.ccs.tencentyun.com",' >> /etc/docker/daemon.json
echo '    "http://hub-mirror.c.163.com",' >> /etc/docker/daemon.json
echo '    "https://reg-mirror.qiniu.com",' >> /etc/docker/daemon.json
echo '    "http://f1361db2.m.daocloud.io",' >> /etc/docker/daemon.json
echo '    "https://registry.docker-cn.com"' >> /etc/docker/daemon.json
echo '  ]' >> /etc/docker/daemon.json
echo '}' >> /etc/docker/daemon.json

# 添加阿里docker安装源
yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
yum makecache fast
yum list docker-ce.x86_64 --showduplicates | sort -r
yum install docker-ce-18.06.3.ce-3.el7 -y
systemctl start docker
systemctl enable docker


# 添加kubernetes 安装源为阿里源
mv kubernetes.repo /etc/yum.repos.d/
setenforce 0
yum install -y kubelet kubeadm kubectl
yum install -y  bash-completion bash-completion-extras
echo "source <(kubectl completion bash)" >> ~/.bashrc
source <(kubectl completion bash)
# 添加 api server loadbalance 配置
docker pull nginx:alpine
mkdir -p /etc/nginx
mv nginx.conf /etc/nginx
chmod +r /etc/nginx/nginx.conf
mv nginx-proxy.service /etc/systemd/system/
systemctl daemon-reload
systemctl start nginx-proxy
systemctl enable nginx-proxy
systemctl status nginx-proxy
echo "you must restart your compute to make the change effect"