#!/bin/bash

MY_REGISTRY="swr.cn-southwest-2.myhuaweicloud.com/zqli"

images=(
    "apache/skywalking-oap-server:9.7.0"
    "apache/skywalking-ui:9.7.0"
    "apache/skywalking-swck:v0.9.0"
    "apache/skywalking-java-agent:9.2.0-java17"
    "apache/skywalking-banyandb:0.7.0"
    "quay.io/jetstack/cert-manager-controller:v1.14.5"
    "quay.io/jetstack/cert-manager-webhook:v1.14.5"
    "quay.io/jetstack/cert-manager-cainjector:v1.14.5"
    "quay.io/jetstack/cert-manager-startupapicheck:v1.14.5"
)

for img in "${images[@]}"; do
    echo "处理: ${img}"
    # 直接拉取原始镜像
    docker pull "${img}"
    # 目标镜像名（保留原始路径，只更换 registry）
    dest="${MY_REGISTRY}/${img}"
    docker tag "${img}" "${dest}"
    docker push "${dest}"
    echo "完成: ${dest}"
    docker rmi "${dest}"
    echo "删除tag：${dest}"
done