# hpav2-cpu-demo.yaml 
```
kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/HPA/test/hpav2/hpav2-cpu-demo.yaml
```
```
[root@master1 HPA ]# kubectl get hpa

[root@master1 HPA ]# kubectl get pod

[root@master1 HPA ]# kubectl get svc
```
```
apt install apache2-utils
while true;do ab -c 1000 -n 2000 http://<cluster IP>/;done

# -c 并发数
# -n 总请求数
```