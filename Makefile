MAKEDIR	:= $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
BUILD	?= $(MAKEDIR)/tmp
M		?= $(BUILD)/milestones

# Targets
deploy: /usr/bin/kubeadm
preference: $(M)/preference
kubeadm-init: $(M)/kubeadm

$(M)/setup:
	sudo apt-get update
	sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
	sudo $(MAKEDIR)/scripts/portcheck.sh
	sudo swapoff -a
	# To remain swap disabled after reboot
	# sudo sed -i '/ swap / s/^\(.*\)$$/#\1/g' /etc/fstab
	mkdir -p $(M)
	touch $@

# https://kubernetes.io/docs/setup/production-environment/container-runtimes/#docker
/usr/bin/docker: | $(M)/setup
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
	sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(shell lsb_release -cs) stable"
	sudo apt-get update
	sudo apt-get install -y docker-ce=18.06.2~ce~3-0~ubuntu
	echo "{\n\
		\"exec-opts\": [\"native.cgroupdriver=systemd\"],\n\
		\"log-driver\": \"json-file\",\n\
		\"log-opts\": {\n\
			\"max-size\": \"100m\"\n\
		},\n\
		\"storage-driver\": \"overlay2\"\n\
	}" | sudo tee /etc/docker/daemon.json
	sudo mkdir -p /etc/systemd/system/docker.service.d
	sudo systemctl daemon-reload
	sudo systemctl restart docker

/usr/bin/kubeadm: | $(M)/setup /usr/bin/docker
	curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
	echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
	sudo apt-get update
	sudo apt-get install -y kubelet kubeadm kubectl
	sudo apt-mark hold kubelet kubeadm kubectl
	echo "KUBELET_EXTRA_ARGS=--cgroup-driver=systemd" | sudo tee /etc/default/kubelet
	sudo systemctl daemon-reload
	sudo systemctl restart kubelet

$(M)/preference: | $(M)/setup /usr/bin/kubeadm
	sudo apt-get install bash-completion
	source /usr/share/bash-completion/bash_completion
	kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl
	touch $@

$(M)/kubeadm: | $(M)/setup /usr/bin/kubeadm
	sudo kubeadm init --pod-network-cidr=192.168.0.0/16
	mkdir -p $(HOME)/.kube
	sudo cp -f /etc/kubernetes/admin.conf $(HOME)/.kube/config
	sudo chown $(shell id -u):$(shell id -g) $(HOME)/.kube/config
	kubectl apply -f https://docs.projectcalico.org/v3.8/manifests/calico.yaml
	kubectl taint nodes --all node-role.kubernetes.io/master-
	touch $@
	echo "Kubernetes control plane node created!"

reset-kubeadm:
	rm -f $(M)/kubeadm
	sudo kubeadm reset -f || true
	# https://blog.heptio.com/properly-resetting-your-kubeadm-bootstrapped-cluster-nodes-heptioprotip-473bd0b824aa
	sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X
