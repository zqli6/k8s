# /data/cni-plugins-linux-amd64-v1.6.2.tgz的获取  
```
docker pull swr.cn-southwest-2.myhuaweicloud.com/zqli_s/cni-plugins-linux-amd64:v1.6.2
```
```
docker create --name cni swr.cn-southwest-2.myhuaweicloud.com/zqli_s/cni-plugins-linux-amd64:v1.6.2 echo
docker cp cni:/data/cni-plugins-linux-amd64-v1.6.2.tgz .
```