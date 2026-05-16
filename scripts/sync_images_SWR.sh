#!/bin/bash

# 1. 定义你的私有仓库前缀 (请根据你的实际 SWR 路径修改)
MY_REGISTRY="swr.cn-southwest-2.myhuaweicloud.com/zqli/google_containers"

# 2. 定义阿里云的源镜像前缀
FROM_REGISTRY="registry.aliyuncs.com/google_containers"

# 3. 这里的镜像列表是根据你刚才 docker images 的输出整理的
# 格式为 "镜像名:版本号"
images=(
    "kube-apiserver:v1.35.0"
    "kube-proxy:v1.35.0"
    "kube-scheduler:v1.35.0"
    "kube-controller-manager:v1.35.0"
    "etcd:3.6.6-0"
    "coredns:v1.13.1"
    "pause:3.10.1"
)

echo "--- 开始同步镜像到私有仓库: ${MY_REGISTRY} ---"

for img in "${images[@]}"; do
    SRC_IMG="${FROM_REGISTRY}/${img}"
    DEST_IMG="${MY_REGISTRY}/${img}"
    
    echo "处理中: ${img}"
    
    # 如果本地没有源镜像，先拉取（以防万一）
    if [[ "$(docker images -q ${SRC_IMG} 2> /dev/null)" == "" ]]; then
        echo "  [Pull] 正在从阿里云拉取..."
        docker pull ${SRC_IMG}
    fi

    # 打标签
    echo "  [Tag] 重命名为私有仓库格式..."
    docker tag ${SRC_IMG} ${DEST_IMG}

    # 推送
    echo "  [Push] 正在推送至私有仓库..."
    docker push ${DEST_IMG}
    
    echo "  [OK] ${img} 同步完成！"
    echo "------------------------------------"
done

echo "所有镜像同步完毕！"
