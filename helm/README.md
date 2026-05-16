# 相关网址  
1. 安装  
<https://helm.sh/docs/intro/install/>  
2. GitHub  
<https://github.com/helm/helm>
3. LZQ的学习文档  
[LZQ学习文档](https://www.yuque.com/jianglai-iayzx/sa1zul/vpmelt03h9qzq32c)  
# 使用方法  
1. 查看[LZQ学习文档](https://www.yuque.com/jianglai-iayzx/sa1zul/vpmelt03h9qzq32c)  
2. 使用方法   
  2. 本地chart包安装和升级  
  ```
  # 创建chart目录
  [root@helm chart ]# helm create myweb
  [root@helm chart ]# tree myweb
  myweb
  ├── Chart.yaml
  ├── charts
  ├── templates
  │   ├── NOTES.txt
  │   ├── _helpers.tpl
  │   ├── deployment.yaml
  │   ├── hpa.yaml
  │   ├── httproute.yaml
  │   ├── ingress.yaml
  │   ├── service.yaml
  │   ├── serviceaccount.yaml
  │   └── tests
  │       └── test-connection.yaml
  └── values.yaml
  [root@helm chart ]# rm -rf myweb-chart/templates/* myweb/charts/
  
  # 可以查看本目录myweb目录
  [root@helm chart ]# tree myweb
  myweb
  ├── Chart.yaml
  ├── templates
  └── values.yaml
  
  # 修改文件并增加templates文件
  [root@helm chart ]# tree myweb
  myweb
  ├── Chart.yaml
  ├── templates
  │   ├── myweb-deployment.yaml
  │   └── myweb-service.yaml
  └── values.yaml
  
  # 打包
  [root@helm chart ]# helm package myweb
  [root@helm chart ]# ls
  myweb  myweb-chart-0.0.1.tgz
  
  # 使用本地文件安装，还可以helm仓库安装和OCI安装
  [root@helm chart ]# helm install myweb myweb-chart-0.0.1.tgz # chart包安装
  [root@helm chart ]# helm install myweb myweb                 # 文件目录安装
  # 可以指定新的values.yaml文件安装
  [root@helm chart ]# helm install myweb -f new_values.yaml myweb-chart-0.0.1.tgz
  
  # 查看状态
  [root@helm chart ]# helm list
  
  # 访问测试
  [root@GitLab ~ ]# kubectl get svc
  NAME            TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)        AGE
  myweb-service   LoadBalancer   10.101.224.114   10.0.0.12     80:32074/TCP   5m32s
  [root@GitLab ~ ]# curl 10.101.224.114
  kubernetes pod-test v0.1!! ClientIP: 10.244.8.0, ServerName: myweb-deployment-56676c868b-dlk8f, ServerIP: 10.244.6.87!
  
  # set指定参数升级(指定values.yaml中镜像版本参数为新版本)
  [root@helm chart ]# helm upgrade --install myweb myweb-chart-0.0.1.tgz --set deployment.imageTag=v0.2
  [root@GitLab ~ ]# curl 10.101.224.114
  kubernetes pod-test v0.2!! ClientIP: 10.244.8.0, ServerName: myweb-deployment-78bbf96999-bgkwp, ServerIP: 10.244.1.137!
  
  # 查看历史版本
  [root@helm chart ]# helm history myweb
  REVISION	UPDATED                 	STATUS    	CHART            	APP VERSION	DESCRIPTION     
  1       	Sat Apr  4 21:13:31 2026	superseded	myweb-chart-0.0.1	1.0.0      	Install complete
  2       	Sat Apr  4 21:21:11 2026	deployed  	myweb-chart-0.0.1	1.0.0      	Upgrade complete
  
  # rollback
  [root@helm chart ]# helm rollback myweb 1
  Rollback was a success! Happy Helming!
  
  # 访问
  [root@GitLab ~ ]# curl 10.101.224.114
  kubernetes pod-test v0.1!! ClientIP: 10.244.8.0, ServerName: myweb-deployment-56676c868b-dgbb4, ServerIP: 10.244.6.89!
  ```
