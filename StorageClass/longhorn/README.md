# 相关网址  
1.GitHub：https://github.com/longhorn/longhorn  
2.[Lzq部署文档](https://www.yuque.com/jianglai-iayzx/wkzfha/cvoagivzrzgz4kyt#uiDV3)

# 部署步骤 
1.lzq SWR仓库版1.12.0
```
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/StorageClass/longhorn/longhorn-1.12.0-lzq.yaml
``` 
2.[GitHub官方文档清单](https://github.com/longhorn/longhorn/blob/master/deploy/longhorn.yaml)

3. swr仓库密码
```
# 1. 创建 Secret（存储 SWR 登录凭据）
kubectl create secret docker-registry swr-auth -n longhorn-system \
  --docker-server=swr.cn-southwest-2.myhuaweicloud.com \
  --docker-username='cn-southwest-2@HST3WBRU8484RY3AGAFX' \
  --docker-password='8eb15bd0873dc162d8be3057ba45653764d344d3926484c1bbf1e1836b2a01cd'

# 2. 绑定到 ServiceAccount
kubectl get pod -n longhron-system -o jsonpath='{range .items[*]}{.spec.serviceAccountName}{"\n"}{end}' \
  | sort -u \
  | while read sa; do
      [ -z "$sa" ] && continue
      echo ">>> patching SA: $sa"
      kubectl patch serviceaccount "$sa" -n longhorn-system \
        -p '{"imagePullSecrets": [{"name": "swr-auth"}]}'
    done
```