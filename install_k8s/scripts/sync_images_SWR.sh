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
    echo "========================================="
    echo "处理镜像: ${img}"
    
    # 1. 拉取原始镜像（自动适配当前 CPU 架构）
    if ! docker pull "${img}"; then
        echo "错误：拉取 ${img} 失败，跳过"
        continue
    fi

    # 2. 生成安全的 tar 文件名（将 / 和 : 替换为 _）
    safe_name=$(echo "${img}" | tr '/:' '_-')
    tar_file="${safe_name}.tar"
    
    echo "保存为文件: ${tar_file}"
    docker save "${img}" -o "${tar_file}"
    
    # 可选：检查保存是否成功
    if [ ! -f "${tar_file}" ]; then
        echo "错误：保存 ${tar_file} 失败"
        continue
    fi
    echo "已保存: $(ls -lh ${tar_file} | awk '{print $5}')"
    
    # 3. 打标签，准备推送到私有仓库
    dest="${MY_REGISTRY}/${img}"
    echo "目标标签: ${dest}"
    docker tag "${img}" "${dest}"
    
    # 4. 推送到华为云 SWR（如果需要）
    if docker push "${dest}"; then
        echo "推送成功: ${dest}"
    else
        echo "推送失败: ${dest}"
    fi
    
    # 5. 删除本地临时标签（不影响原始镜像）
    docker rmi "${dest}" >/dev/null 2>&1
    
    echo "-----------------------------------------"
done

echo "所有镜像处理完毕。tar 文件列表："
ls -lh *_*.tar 2>/dev/null | awk '{print $9, $5}'