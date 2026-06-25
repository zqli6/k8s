# 1. 官方链接
   * 项目  
     <https://github.com/kubernetes/ingress-nginx/>  
   * ingress-nginx部署yaml  
     <https://github.com/kubernetes/ingress-nginx/blob/main/deploy/static/provider/cloud/deploy.yaml>  
# 2. 安装metalLB动态分配external IP  
- 如果多节点自动分配external IP，需要安装metalLB，[点此查看](https://gitee.com/zqli6/k8s/tree/main/metalLB)  
- 如果只是单节点，那么下方yaml中已经配置了固定external IP，按下方教程手动在固定节点网卡增加external IP即可
# 3. 部署ingress-nginx 使用 Lzq SWR 镜像加速yaml
1. 部署ingress-nginx  
      1.1 x86部署  
      ```
      kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/ingress/ingress-controller-lzq.yaml
      ```  
      1.2 arm部署  
      ```
      kubectl apply -f https://gitee.com/zqli6/k8s/raw/main/ingress/ingress-controller-lzq-arm.yaml
      ```
2. 优化(arm版有调整，两个版本最好都看一下)
   1. 设置副本数为2，高可用
   2. 设置externalIPs `10.0.0.99`
      在k8s集群中的运行ingress-nginx-controller的Pod节点上添加externalIPs指定的IP地址  
      写入/etc/rc.loccal实现开机加载，或配置静态IP地址  
      ```
      ip a a 10.0.0.99/24 dev eth0 label eth0:1
      cat >>/etc/rc.loccal<<EOF
      #!/bin/bash
      ip a a 10.0.0.99/24 dev eth0 label eth0:1
      EOF
      chmod +x /etc/rc.local
      systemctl enable rc-local
      systemctl start rc-local
      ```  
# 4. 声明 ingress 资源
  在部署服务应用时，需要创建对应应用的ingress资源 
   1. 命令式  
   ```
   kubectl create ingress NAME --rule=domain/url=service:port[,tls[=secret]] [options]
   kubectl create service clusterip pod-test1 --tcp=80:80
   kubectl create ingress demo-ingress --rule="www.wang.org/=pod-test1:80" --class=nginx -o yaml --dry-run=client
   ``` 
   2. 清单示例：  
  ```
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
  namespace: default
  annotations:
    # 指定 Ingress Controller 类型
    kubernetes.io/ingress.class: nginx
    # 强制将 http 重定向到 https（如果配置了 tls）
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    # 后端服务使用 http 协议（默认即可）
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  # TLS 配置（可选，如果不需要 https 可以删除整个 tls 字段）
  tls:
  - hosts:
      - example.com
    secretName: example-tls-secret   # 需要提前创建包含证书的 Secret
  rules:
  - host: example.com                # 域名
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-service          # 你的 Service 名称
            port:
              number: 80              # Service 暴露的端口
  ```
  
