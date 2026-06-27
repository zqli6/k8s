# 1. 相关网址  
1.1. GitHub：https://github.com/topolvm/topolvm  
1.2. Lzq文档：[点击查看](https://www.yuque.com/jianglai-iayzx/wkzfha/rk3ydmhvzgqprmww#UZpLD)  

# 2. 部署  
## 2.1. 前置准备  
[详见Lzq文档](https://www.yuque.com/jianglai-iayzx/wkzfha/rk3ydmhvzgqprmww#x8ppp)   

## 2.2 创建PV及VG  
1) 把裸盘做成 LVM 物理卷  
```
sudo pvcreate /dev/sdb
```
2) 创建卷组（命名建议有语义，如 ssd-vg / hdd-vg）
```
sudo vgcreate node-vg /dev/sdb
```
3) 验证
```
sudo pvs
sudo vgs
```

## 2.3 创建 thin pool
```
# 取 VG 总大小的 80% 作为 thin pool
VG_SIZE=$(sudo vgs --noheadings --nosuffix --units g -o vg_size node-vg | tr -d ' ')
THIN_SIZE=$(echo "$VG_SIZE * 0.8" | bc | cut -d'.' -f1)

sudo lvcreate -L ${THIN_SIZE}G -T node-vg/thin-pool
sudo lvs
```  
> [thin pool的作用解析](https://www.yuque.com/jianglai-iayzx/wkzfha/rk3ydmhvzgqprmww#gskog)

## 2.3 安装 cert-manager  
2.3.1. [参考zqli6/skywalking中cert-manager部署](https://gitee.com/zqli6/skywalking/tree/main/k8s/manifest#1-%E9%83%A8%E7%BD%B2cert-manager)  
2.3.2. [参考Lzq文档](https://www.yuque.com/jianglai-iayzx/wkzfha/rk3ydmhvzgqprmww#hOUYF)  

## 2.4. 安装 TopoLVM  
2.4.1. Helm Lzq SWR 加速镜像安装  
2.4.1.1 创建名称空间并打标签[必须]  
```
kubectl create namespace topolvm-system
kubectl label namespace topolvm-system topolvm.io/webhook=ignore
```
```
wget https://gitee.com/zqli6/k8s/raw/main/StorageClass/topolvm/topolvm-16.1.1.tgz \
&& helm install topolvm -n topolvm-system topolvm-16.1.1.tgz \
-f https://gitee.com/zqli6/k8s/raw/main/StorageClass/topolvm/topolvm-values-arm-lzq.yaml
```  
>topolvm-values-arm-lzq.yaml中的修改说明见本仓库文件或查看[Lzq文档相关章节](https://www.yuque.com/jianglai-iayzx/wkzfha/rk3ydmhvzgqprmww#dj7FU)  

2.4.2. Helm 官方安装  
详见：[Lzq topolvm文档](https://www.yuque.com/jianglai-iayzx/wkzfha/rk3ydmhvzgqprmww#BLTMt)



