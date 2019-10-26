#!/bin/bash

# Copyright 2017-present Open Networking Foundation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Service name:             Port number
# Kubernetes API server:    6443
# etcd server client API:   2379-2380
# Kubelet API:              10250
# kube-scheduler:           10251
# kube-controller-manager:  10252

declare -a portlist=("6443" "2379" "2380" "10250" "10251" "10252")

number_of_ports_in_use=0

#Below loop is to check whether any port in the list is already being used
for port in "${portlist[@]}"
do
        if netstat -lntp | grep :":$port" > /dev/null ; then
                used_process=$(netstat -lntp | grep :":$port" | tr -s ' ' | cut -f7 -d' ')
                echo "ERROR: Process with PID/Program_name $used_process is already listening on port: $port needed by Kubernetes"
                number_of_ports_in_use=$((number_of_ports_in_use+1))
        fi
done

#If any of the ports are already used then the user will be notified to kill the running services before installing Kubernetes
if [ $number_of_ports_in_use -gt 0 ]
    then
        echo "Kill the running services mentioned above before proceeding to install Kubernetes"
        echo "Terminating make"
        exit 1
fi

#The ports that are required by Kubernetes components will be added to the reserved port list
var=$(printf '%s,' "${portlist[@]}")
echo "$var" > /proc/sys/net/ipv4/ip_local_reserved_ports
echo "SUCCESS: Added ports required for Kubernetes services to ip_local_reserved_ports"

