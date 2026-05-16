```
ubectl apply -f https://gitee.com/zqli6/k8s/raw/main/HPA/test/hpav1/php-apache.yaml -f https://gitee.com/zqli6/k8s/raw/main/HPA/test/hpav1/hpa-php-apache.yaml
```
查看信息
```
[root@master1 HPA ]# kubectl get pod
NAME                          READY   STATUS    RESTARTS   AGE
load-generator                0/1     Error     0          104s
php-apache-76f5587cd4-c9f7p   1/1     Running   0          5m14s

[root@master1 HPA ]# kubectl get svc
NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
kubernetes   ClusterIP   10.96.0.1       <none>        443/TCP   174m
php-apache   ClusterIP   10.106.82.119   <none>        80/TCP    5m18s

```
#测试访问(替换cluster IP)
```
kubectl run -i --tty load-generator --rm --image=registry.cn-beijing.aliyuncs.com/wangxiaochun/busybox:1.32.0 --restart=Never -- /bin/sh -c "while sleep 0.01; do wget -q -O- http://<php-apache-IP>; done"
```
```
while sleep 0.01; do curl <php-apache-IP>; done
```
```
#观察HPA的指标变化
[root@master1 ~]#kubectl get hpa php-apache --watch
```