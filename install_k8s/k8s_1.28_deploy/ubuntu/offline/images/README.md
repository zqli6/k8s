见根目录README.md，从LZQ SWR仓库拉取镜像：

```
docker pull swr.cn-southwest-2.myhuaweicloud.com/zqli_s/k8s_1.28_deploy_images:26.10.11

docker create --name images swr.cn-southwest-2.myhuaweicloud.com/zqli_s/k8s_1.28_deploy_images:26.10.11 echo

docker cp images:/data/ .
```

```
mkdir -p /mnt/images

ctr pull swr.cn-southwest-2.myhuaweicloud.com/zqli_s/k8s_1.28_deploy_images:26.10.11

ctr image mount swr.cn-southwest-2.myhuaweicloud.com/zqli_s/k8s_1.28_deploy_images:26.10.11 /mnt/images

cp /mnt/images .
```