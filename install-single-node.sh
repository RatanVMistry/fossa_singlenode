#!/bin/bash

if [ "$(id -u)" != "0" ]; then
  exec sudo "$0" "$@"
fi

cd /opt/
#Check OS to use appropriate package manager & turn off selinux for Centos 7
if [ -f /etc/redhat-release ] || [ -f /etc/centos-release ]; then
  
  OS_CHECK=yumpm

elif [ -f /etc/lsb-release ]; then
  
  OS_CHECK=aptgetpm

else
  
  OS_CHECK=yumpm

fi


#Update packages
if [ "$OS_CHECK" = "aptgetpm" ]; then

    echo -e " *************** Installation for Ubuntu *************** \n"
    echo -e "*************** apt-get update -y  *************** \n"

    sudo apt-get update -y

    echo -e "*************** apt-get install -y expect wget nc git *************** \n"
    #Install expect
    sudo apt-get install -y expect wget nc git
    ################################################################################################

    #Install Docker

    echo -e "*************** Install Docker start  *************** \n"
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    echo -e "*************** Installed Docker   *************** \n"
    echo -e "*************** service  Docker start  *************** \n"
    sudo systemctl start docker

    echo -e "*************** Install Kubernetes start  *************** \n"
    sudo apt-get update && sudo apt-get install -y apt-transport-https curl
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
    cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
    sudo apt-get update
    sudo apt-get install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl
    echo -e "*************** Install Kubernetes Done  *************** \n"

fi

if [ "$OS_CHECK" = "yumpm" ]; then
    echo -e " *************** Installation for CentOS *************** \n"
    echo -e " *************** yum update -y *************** \n"
    sudo yum update -y
    #Install expect
    echo -e " *************** yum install -y expect *************** \n"
    sudo yum install -y expect
    #Install XXD which is used in the configure.sh
    echo -e " *************** yum install -y vim-common *************** \n"
    sudo yum install -y vim-common
    echo -e " *************** yum install -y wget nc git *************** \n"
    yum install -y wget nc git
    #Install docker ce
    echo -e "*************** Install Docker start  *************** \n"
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    sudo yum install docker-ce -y
    echo -e "*************** Installed Docker   *************** \n"
    echo -e "*************** service  Docker start  *************** \n"
    sudo systemctl start docker
    sudo systemctl enable docker.service
    echo -e "*************** Install Kubernetes start  *************** \n"
    cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

# Set SELinux in permissive mode (effectively disabling it)
    setenforce 0
    sed -i 's/enforcing/disabled/g' /etc/selinux/config

    yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

    systemctl enable --now kubelet
  echo -e "*************** Install Kubernetes Done  *************** \n"
fi
################################################################################################
################################################################################################
echo -e "*************** swapoff –a  *************** \n"
sudo swapoff –a
echo -e "*************** systemctl daemon-reload  *************** \n"
sudo systemctl daemon-reload
echo -e "*************** systemctl restart kubelet  *************** \n"
sudo systemctl restart kubelet

echo "net.bridge.bridge-nf-call-iptables=1" | sudo tee -a /etc/sysctl.conf
#enable iptables immediately:
sudo sysctl -p
#Initialize the cluster (run only on the master)
echo -e "*************** kubeadm init --pod-network-cidr=10.244.0.0/16  *************** \n"
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
#set up local kubeconfig:
echo -e "*************** Setup local kubeconfig  *************** \n"
mkdir -p $HOME/.kube

sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config

sudo chown $(id -u):$(id -g) $HOME/.kube/config

sudo chmod +r $HOME/.kube/config
echo -e "*************** Kubeconfig set  *************** \n"
#Apply Flannel CNI network overlay:
echo -e "*************** Install Flannel CNI  *************** \n"
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
#Verify the kubernetes node:
echo -e "*************** Get node  *************** \n"
kubectl get nodes
#Remove tain from the master node
echo -e "*************** Taint Master Node  *************** \n"
kubectl taint nodes --all node-role.kubernetes.io/master-
###################################################################################################
#Deplyo FOSSA
###################################################################################################
cd /opt/
#Clone Github repo for Fossa
echo -e "*************** Clone Fossa  *************** \n"
git clone https://github.com/chiphwang/fossa_helm.git
#create FOSSA namespace
echo -e "*************** Create NAmeSpace fossa  *************** \n"
kubectl create ns fossa
#Create FOSSA directories
cd /opt; mkdir -p fossa; cd fossa; mkdir -p database; mkdir -p minio; chmod 777 database; chmod 777 minio
# Create image pull secret for Quay to pull images
cd /opt/fossa_helm/

# install helm
echo -e "*************** Install Tiller  *************** \n"
curl -LO https://git.io/get_helm.sh
chmod 700 get_helm.sh
./get_helm.sh

sudo echo "export PATH=$PATH:/usr/local/bin" >> /etc/bashrc
source /etc/bashrc
echo -e "*************** Tiller Installed  *************** \n"
# install Tiller
echo -e "*************** Tiller Initialize  *************** \n"

kubectl -n kube-system create serviceaccount tiller

kubectl create clusterrolebinding tiller \
  --clusterrole=cluster-admin \
  --serviceaccount=kube-system:tiller

# initialize Helm

helm init --service-account tiller
echo -e "*************** Tiller initialized  *************** \n"

# move to working directory
cd /opt/fossa_helm

while true; do
  node_status=`kubectl get node | awk 'FNR == 2 {print $2}'`
  echo -e "$node_status \n"
  if [ "$node_status" == "Ready" ]; then
    echo -e "node is ready \n"
    break
  else
    sleep 60
    echo -e "wait for node ready"
  fi
done

while true; do
  pod_status=`kubectl get pod -n kube-system | grep tiller-deploy | awk 'FNR == 1 {print $3}'`
  echo -e "$pod_status \n"
  if [ "$pod_status" == "Running" ]; then
    echo -e "pode is ready \n"
    break
  else
    sleep 60
    echo -e "wait for tiller ready"
  fi
done


echo -e "*************** Continue installing helm  *************** \n"
