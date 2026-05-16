1. k8s安装GitLab的官方文档  
<https://docs.gitlab.com/operator/installation/>
2. 注意GitLab需要极大资源，确保资源足够
3. 安装步骤

| 步骤 | 操作内容 | 关键命令示例 |
| :----- | :----- | :--- |
| Step 1 | 安装 Metrics Server | `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml` |
| Step 2 | 安装 cert-manager | `kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.0/cert-manager.yaml` |
| Step 3 | 安装 Ingress Nginx | `kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml` |
| Step 4 | 安装 GitLab Operator | `kubectl apply -f https://gitlab.com/api/v4/projects/18899486/packages/generic/gitlab-operator/2.9.0/gitlab-operator-kubernetes-2.9.0.yaml` |

4. 使用本文件
```
kubectl apply -f https://github.com/zqli6/k8s/raw/refs/heads/main/install_yaml/gitlab/components.yaml  
kubectl apply -f https://github.com/zqli6/k8s/raw/refs/heads/main/install_yaml/gitlab/cert-manager.yaml  
kubectl apply -f https://github.com/zqli6/k8s/raw/refs/heads/main/install_yaml/gitlab/deploy.yaml  
kubectl apply -f https://github.com/zqli6/k8s/raw/refs/heads/main/install_yaml/gitlab/gitlab-operator-kubernetes-2.9.0.yaml
```
