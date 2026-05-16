# Kubernetes Manifests for Jenkins Deployment

```
Refer https://devopscube.com/setup-jenkins-on-kubernetes-cluster/ for step by step process to use these manifests.

https://www.jenkins.io/doc/book/installing/kubernetes/
git clone https://github.com/scriptcamp/kubernetes-jenkins
```
# 1 deb包安装
```
apt install ./jenkins_2.541.2_all.deb
yum localinstall jenkins_2.541.2_all.deb
```

# 1 部署前准备
## 1.1 节点环境准备
因为PVC的存储类使用了WaitForFirstConsumer绑定模式，所以查看节点是否有污点导致Pod无法调度
```
[root@master1 jenkins ]# kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
NAME              TAINTS
master1.lzq.org   [map[effect:NoSchedule key:node-role.kubernetes.io/control-plane]]
node1.lzq.org     <none>
node2.lzq.org     <none>
node3.lzq.org     <none>
或
[root@master1 jenkins ]# kubectl describe node | grep Taints
```
**什么是污点 (Taints)？**  
    污点允许一个节点排斥一类特定的 Pod。它由三部分组成：Key、Value 和 Effect。  
常见的 Effect（效果）有三种：  
🌏  **NoSchedule**：     新的 Pod 不会被调度到该节点，除非它有匹配的容忍度（Toleration）。但已经在运行的 Pod 不受影响。  
🌎**PreferNoSchedule**： 软限制。系统尽量不调度，但实在没地方去时也可能塞进来。  
🌍   **NoExecute**：     最狠的一招。不仅不让新 Pod 来，如果节点上现有的 Pod 没有容忍度，会被直接驱逐。  
***
**设置污点 (Add Taint)**  
语法：kubectl taint nodes <节点名> key=value:effect
```
# 给名为 node1 的节点增加一个污点，key是 gpu，value是 true，效果是不允许调度
kubectl taint nodes node1 gpu=true:NoSchedule
```
**取消污点 (Remove Taint)**  
取消污点的命令和设置几乎一样，只需要在 Effect 后面加一个 减号 (-)。
```
移除指定 key 的某个效果：
kubectl taint nodes node1 gpu=true:NoSchedule-  

移除k8s控制平面的污点
kubectl taint nodes master1.lzq.org node-role.kubernetes.io/control-plane:NoSchedule-

移除指定 key 的所有效果：
kubectl taint nodes node1 gpu-
```
**补充：Pod 如何“忍受”污点？**  
如果你希望某个特定的 Pod 能够运行在有污点的节点上，你需要在 Pod 的 YAML 中配置 tolerations
```
spec:
  tolerations:
  - key: "gpu"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"
```
## 1.2 controller应用准备  
metalLB部署详细说明见：  
请优先按此链接部署  
🪴🌲🌴🌳🌵🌾🥬  
<https://github.com/zqli6/k8s/blob/main/metalLB/README.md>  
🌻☘️🌱🪴🥀🌸💐

```
kubectl apply -f https://github.com/zqli6/k8s/raw/refs/heads/main/metalLB/metallb-native-v0.19.0-lzq.yaml
```
metallb-IPAddressPool应用
```
kubectl apply -f https://github.com/zqli6/k8s/raw/refs/heads/main/metalLB/service-metallb-IPAddressPool.yaml
```
metallb-L2Advertisement应用  
注释了限制网卡，可以取消注释修改interface
```
kubectl apply -f https://github.com/zqli6/k8s/raw/refs/heads/main/metalLB/service-metallb-L2Advertisement.yaml
```

ingress-controller部署  
```
kubectl apply -f https://raw.githubusercontent.com/zqli6/k8s/main/ingress/ingress-controller-lzq.yaml 
```


# 1 在node1节点准备目录  
PV的节点亲和性配置指定node1的域名，需替换：
```
sed -i 's#node1.lzq.org#你的node1域名#' 03-volume.yaml
```
修改ingress暴露的域名：
```
sed -i 's#jenkins.lzq.org#j你的Jenkins域名#' 06-ingress.yaml
```
创建PV文件夹：
```
mkdir -p /data/jenkins
```

# 2 应用清单文件

```
[root@master1 kubernetes-jenkins]#ls
01-namespace.yaml  02-rbac.yaml  03-volume.yaml  04-deployment.yaml   05-service.yaml  06-ingress.yaml  README.md

[root@master1 kubernetes-jenkins]#kubectl apply -f .
```

# 3 确认结果

```bash
oot@master1 ~]#kubectl get all -n devops
NAME                           READY   STATUS    RESTARTS   AGE
pod/jenkins-58c85cb467-zbwxk   1/1     Running   0          15m

NAME              TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)                                   AGE
service/jenkins   LoadBalancer   10.104.233.208   10.0.0.12     8080:32000/TCP                            5s

NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/jenkins   1/1     1            1           15m

NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/jenkins-58c85cb467   1         1         1       15m


[root@master1 ~]#kubectl get -n devops  ingress
NAME             CLASS   HOSTS              ADDRESS     PORTS   AGE
jenkins          nginx   jenkins.lzq.org   10.0.0.10   80      45s


[root@node1 ~]#ls /data/jenkins/
config.xml               hudson.model.UpdateCenter.xml     jobs              plugins     secret.key.not-so-secret  updates      users
copy_reference_file.log  jenkins.telemetry.Correlator.xml  nodeMonitors.xml  secret.key  secrets                   userContent  war

```

# 4 访问 Jenkins

```bash
#查看访问密码
#方法1: 
[root@master1 ~]#kubectl exec -n devops jenkins-58c85cb467-zbwxk -- cat /var/jenkins_home/secrets/initialAdminPassword
1a6d14ac85874752b74f803797df0797
#方法2:
[root@node1 ~]#cat /data/jenkins/secrets/initialAdminPassword
1a6d14ac85874752b74f803797df0797

#访问Jenkins
#方法1:ingress访问,域名jenkins.lzq.org解析至10.0.0.10(前提:安装ingress-controller)
http://jenkins.lzq.org

#访问2: LoadBlancer SVC 访问 external IP
http://10.0.0.10
```

