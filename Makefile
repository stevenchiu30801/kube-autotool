SHELL	:= /bin/bash
MAKEDIR	:= $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
BUILD	?= $(MAKEDIR)/tmp
M		?= $(BUILD)/milestones

# 18.06.2~ce~3-0~ubuntu in Kubernetes document
DOCKER_VERSION	?= 18.06.2

K8S_VERSION		?= 1.16.2

CALICO_VERSION		?= 3.8
CALICOCTL_VERSION	?= 3.8.5

HELM_VERSION	?= 3.0.0
HELM_PLATFORM	?= linux-amd64

GO_VERSION	?= 1.13.5

# Targets
deploy: $(M)/kubeadm
install: /usr/bin/kubeadm /usr/local/bin/helm /usr/local/bin/calicoctl
preference: $(M)/preference

$(M)/setup:
	sudo $(MAKEDIR)/scripts/portcheck.sh
	sudo swapoff -a
	# To remain swap disabled after reboot
	# sudo sed -i '/ swap / s/^\(.*\)$$/#\1/g' /etc/fstab
	mkdir -p $(M)
	touch $@

# https://kubernetes.io/docs/setup/production-environment/container-runtimes/#docker
/usr/bin/docker: | $(M)/setup
	sudo apt-get update
	sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
	sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(shell lsb_release -cs) stable"
	sudo apt-get update
	sudo apt-get install -y docker-ce=${DOCKER_VERSION}*
	# Currently, systemd would report error in kubelet logs on both ubuntu Xenial and Bionic
	# Please refer to https://github.com/kubernetes/kubernetes/issues/76531
	# echo -e "{\n\
	# 	\"exec-opts\": [\"native.cgroupdriver=systemd\"],\n\
	# 	\"log-driver\": \"json-file\",\n\
	# 	\"log-opts\": {\n\
	# 		\"max-size\": \"100m\"\n\
	# 	},\n\
	# 	\"storage-driver\": \"overlay2\"\n\
	# }" | sudo tee /etc/docker/daemon.json
	# sudo mkdir -p /etc/systemd/system/docker.service.d
	# sudo systemctl daemon-reload
	# sudo systemctl restart docker

# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#installing-kubeadm-kubelet-and-kubectl
/usr/bin/kubeadm: | $(M)/setup /usr/bin/docker
	sudo apt-get update
	sudo apt-get install -y apt-transport-https curl
	curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
	echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
	sudo apt-get update
	sudo apt-get install -y kubelet=${K8S_VERSION}-* kubeadm=${K8S_VERSION}-* kubectl=${K8S_VERSION}-*
	sudo apt-mark hold kubelet kubeadm kubectl
	# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#configure-cgroup-driver-used-by-kubelet-on-control-plane-node
	# When using Docker, kubeadm will automatically detect the cgroup driver for the kubelet
	# echo "KUBELET_EXTRA_ARGS=--cgroup-driver=systemd" | sudo tee /etc/default/kubelet
	# sudo systemctl daemon-reload
	# sudo systemctl restart kubelet

# https://helm.sh/docs/intro/install/#from-the-binary-releases
/usr/local/bin/helm: | $(M)/setup
	curl -L -o ${BUILD}/helm.tgz https://get.helm.sh/helm-v${HELM_VERSION}-${HELM_PLATFORM}.tar.gz
	cd ${BUILD}; tar -zxvf helm.tgz
	sudo mv ${BUILD}/${HELM_PLATFORM}/helm $@
	sudo chmod a+x $@
	rm -r ${BUILD}/helm.tgz ${BUILD}/${HELM_PLATFORM}

# https://docs.projectcalico.org/v3.10/getting-started/calicoctl/install
/usr/local/bin/calicoctl: | $(M)/setup
	curl -O -L https://github.com/projectcalico/calicoctl/releases/download/v${CALICOCTL_VERSION}/calicoctl
	sudo chmod +x calicoctl
	sudo chown root:root calicoctl
	sudo mv calicoctl $@
	# https://docs.projectcalico.org/v3.10/getting-started/calicoctl/configure/
	sudo mkdir -p /etc/calico
	echo -e "apiVersion: projectcalico.org/v3\n\
	kind: CalicoAPIConfig\n\
	metadata:\n\
	spec:\n\
	  datastoreType: \"kubernetes\"\n\
	  kubeconfig: \"/etc/kubernetes/admin.conf\"" | sudo tee /etc/calico/calicoctl.cfg

$(M)/preference: | /usr/bin/kubeadm /usr/local/bin/helm
	# https://kubernetes.io/docs/tasks/tools/install-kubectl/#enabling-shell-autocompletion
	sudo apt-get install bash-completion
	kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl
	# Avoid error on completion of filename following helm repository field
	# E.g. helm install mychart ./mychart
	#                             ^
	#                             Would pop error related to tail command when hit tab for completion
	helm completion bash | sed "s/tail +2/tail +2 2>\/dev\/null/g" | sudo tee /etc/bash_completion.d/helm
	touch $@
	@echo -e "Please reload your shell or source the bash-completion script to make autocompletion work:\n\
	    source /usr/share/bash-completion/bash_completion"

# https://golang.org/doc/install#install
/usr/local/go:
	curl -O -L https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz
	sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
	echo -e '\nexport PATH=$$PATH:/usr/local/go/bin' >> $(HOME)/.profile
	rm go${GO_VERSION}.linux-amd64.tar.gz
	@echo -e "Please reload your shell or source $$HOME/.profile to apply the changes:\n\
		source $$HOME/.profile"

# https://github.com/containernetworking/plugins
cni-plugins-update: | /usr/bin/kubeadm /usr/local/go
	-git clone https://github.com/containernetworking/plugins /tmp/plugins
	cd /tmp/plugins; git pull
	export PATH=$$PATH:/usr/local/go/bin; cd /tmp/plugins; ./build_linux.sh
	sudo cp /tmp/plugins/bin/* /opt/cni/bin

# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
$(M)/kubeadm: | $(M)/setup /usr/bin/kubeadm
	sudo kubeadm init --pod-network-cidr=192.168.0.0/16
	mkdir -p $(HOME)/.kube
	sudo cp -f /etc/kubernetes/admin.conf $(HOME)/.kube/config
	sudo chown $(shell id -u):$(shell id -g) $(HOME)/.kube/config
	# https://docs.projectcalico.org/v3.10/getting-started/kubernetes/installation/calico
	# To use a pod CIDR different from 192.168.0.0/16, please replace it in calico.yaml with your own
	kubectl apply -f https://docs.projectcalico.org/v${CALICO_VERSION}/manifests/calico.yaml
	# https://github.com/intel/multus-cni/blob/master/doc/quickstart.md
	# -git clone https://github.com/intel/multus-cni.git /tmp/multus
	# cat /tmp/multus/images/multus-daemonset.yml | kubectl apply -f
	kubectl apply -f https://raw.githubusercontent.com/intel/multus-cni/master/images/multus-daemonset.yml
	kubectl taint nodes --all node-role.kubernetes.io/master-
	touch $@
	@echo "Kubernetes control plane node created!"

# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#tear-down
reset-kubeadm:
	rm -f $(M)/setup $(M)/kubeadm
	sudo kubeadm reset -f || true
	sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X
