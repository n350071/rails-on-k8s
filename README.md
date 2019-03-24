# rails-on-k8s
## Purpose
以下を目指す

- [x] 第一段階 : Railsアプリをminikubeで動かせる(hello yay)
- [x] 第二段階 : Railsアプリのコードベースを変更したら、それがminikube上で反映されていることが確認できる
- [x] 第三段階 : RailsアプリをGKEにデプロイして公開できる
- [ ] 第四段階 : RailsアプリのIPを固定化し、domainを与え、https化する
- [ ] 第五段階 : GitOps式のCICD pipeline を実現する

## 注意
`.gitignore`にて、Railsのファイルを無視しています。
適宜、外してください。

## 実行
### 第一段階
#### 0. 前提条件
- docker for mac がインストールされていること
- kubectl がインストールされていること
- minikube がインストールされていること

#### 1. Rails new したコードベースの準備
Docker buildする
```
docker build . -t rails-on-k8s
docker run --rm -v $PWD:$PWD -w $PWD rails-on-k8s bundle exec rails new . --database=mysql --skip-test
```

DB設定、config/database.ymlを開いて、`password`と`host`を修正する
```
password: <%= ENV.fetch("RAILS_DB_PASSWORD") %>
host: mysql
```

#### 2. Minikubeを起動して、クラスタを作成する
```
minikube start
```
(必要なら、`minikube delete`してから )


#### 3. [skaffold](https://skaffold.dev/docs/)を利用する

##### 概要
skaffoldは、kubernetesに対して、Google製のビルド〜デプロイまでを行ってくれるコマンドラインツール。
開発環境において、ビルドしたイメージをレジストリにアップせずに、直接kubernetesのpodに入れてくれる。

##### インストール、設定、実行
インストール
```
brew install skaffold
```
[skaffold.yaml](https://github.com/GoogleContainerTools/skaffold/blob/master/examples/getting-started/skaffold.yaml)を設置、build.artifacts.imageを、任意の<IMAGE_NAME>に書き換える。deploy.kubectl.manifestsの位置をk8sディレクトリ以下に設定する。

```
skaffold dev --cache-artifacts
```
--cache-artifacts : キャッシュする ($HOME/.skaffold/cache)
これで、ローカルで変更があるたびに、kubernetesの<IMAGE_NAME>を使うpod内のcontainerが置き換わる。

##### 詳細
- [Reference cli dev](https://skaffold.dev/docs/references/cli/#skaffold-dev)
- [skaffold.yaml](https://skaffold.dev/docs/references/yaml/)
- [参考記事](https://qiita.com/tomoyamachi/items/660bd7bb3afff8340307#skaffold%E3%81%AB%E3%81%A4%E3%81%84%E3%81%A6)


#### 4. Minikubeにリソースを配置する

リソース配置
```
kubectl create secret generic mysql-pass --from-literal=password=<PASSWORD>
kubectl apply -f .k8s/k8s-mysql.yaml
kubectl apply -f .k8s/k8s-rails.yaml
```

DBを作成する。
<POD_NAME>を確認し、コンテナにログインし、
```
kubectl get pods
kubectl exec -it <POD_NAME> /bin/bash
```

db:createを実行する
```
# bundle exec rails db:create
Created database 'rails-on-k8s_development'
Created database 'rails-on-k8s_test'
```

リソース確認
```
kubectl get pvc
kubectl get deployments
kubectl get pods
kubectl describe pods -l app=rails
kubectl get services
```

describeで詳細を見てみると、この時点では、rails server起動できないので、railsのpodが`CrashLoopBackOff`になっているが、Eventsのイメージをpullできていれば問題なし(予定通り)。

minikubeから、rails serviceに対して、EXTERNAL-IPを与える(その後に`kubectl get services`をしても出てこないが..)
```
minikube service rails --url
```
なお、 `minikube service rails`でブラウザが開く。

#### 備考
- クラスタ内で完結させたかったので、docker-composeを使わずに、k8s内のコンテナに入ってdb:createをする作業が入ってしまった。つまり、もっと綺麗な流れにしたい。
- database設定のhostも、Secretsリソースから読み取るようにしたい

### 第二段階
設定変更が反映されている

### 第三段階
#### GKEにプロジェクトをつくり、アクティベート(課金可能)する
[gcloud install](https://cloud.google.com/sdk/docs/downloads-interactive?hl=ja)

```
gcloud projects create <PROJECT-ID>
gcloud projects list
gcloud config list
gcloud config set project <PROJECT-ID>
gcloud config get-value project
```

[支払い情報を設定(Billing設定)](https://console.cloud.google.com/billing/linkedaccount)後に以下の設定を行う
```
gcloud services enable container.googleapis.com
gcloud services list --available
```
(現時点で、予算設定を超えているとサービスをenableできないようなので、サービス追加できない場合は確認してみてください。)

[gcloud コマンドリファレンス](https://cloud.google.com/sdk/gcloud/reference/projects/)


#### GKEにクラスタを作成する

```
gcloud container clusters create <CLUSTER-NAME> --num-nodes=2 --preemptible
```
クラスタのサイズと、リソースの使用量によって値段が変わってくるみたい。
- [料金の詳細説明](https://cloud.google.com/kubernetes-engine/pricing)
- [料金表](https://cloud.google.com/compute/pricing)
- [料金シミュレーター](https://cloud.google.com/products/calculator/#tab=container)
- [クラスタ作成コマンドリファレンス](https://cloud.google.com/products/calculator/#tab=container)

品質保証のないバージョンでの、デフォルトの`n1-standard-1`ノードを２つ注文で、$14.60の予定(¥1,600)

#### クラスタに対して、Minikubeにやったのとほぼ同じことをする
##### 現在のソースコードを、GCPのリポジトリに置く
https://cloud.google.com/container-registry/docs/pushing-and-pulling?hl=en_US&_ga=2.128219916.-1854617211.1547984722

最新の状況を固めて、
```
docker build . -t rails-on-k8s
```

dockerをgcloudで認証し、
```
$gcloud auth configure-docker

The following settings will be added to your Docker config file located at [~/.docker/config.json]:
 {
  "credHelpers": {
    "gcr.io": "gcloud",
    "us.gcr.io": "gcloud",
    "eu.gcr.io": "gcloud",
    "asia.gcr.io": "gcloud",
    "staging-k8s.gcr.io": "gcloud",
    "marketplace.gcr.io": "gcloud"
  }
}

Do you want to continue (Y/n)?  Y

Docker configuration file updated.
```

imageにtagをつける
```
docker tag [SOURCE_IMAGE] [HOSTNAME]/[PROJECT-ID]/[IMAGE]
docker tag rails-on-k8s asia.gcr.io/shirofune-labo-rails-on-k8s/rails-on-k8s
```

pushする
```
docker push [HOSTNAME]/[PROJECT-ID]/[IMAGE]
docker push asia.gcr.io/shirofune-labo-rails-on-k8s/rails-on-k8s
```

###### [skaffold](https://skaffold.dev/docs/)を使うパターン
...検証予定


##### kubectlでリソース配置
まず、つながり先を確認
```
kubectl config current-context
```

**railsは、イメージ名がローカルと違うので、ファイルを分けた**
```
kubectl create secret generic mysql-pass --from-literal=password=<PASSWORD>
kubectl apply -f .k8s/k8s-mysql.yaml
kubectl apply -f .k8s/gke-rails.yaml
```

DBを作成する。
<POD_NAME>を確認し、コンテナにログインし、
```
kubectl get pods
kubectl exec -it <POD_NAME> /bin/bash
```

db:createを実行する
```
# bundle exec rails db:create
Created database 'rails-on-k8s_development'
Created database 'rails-on-k8s_test'
```

リソース確認
```
kubectl get pvc
kubectl get deployments
kubectl get pods
kubectl describe pods -l app=rails
kubectl get services
```

EXTERNAL-IPが発行されるのを待ち、発行されたら、そこへアクセスする

##### リソース足りない問題
```
Does not have minimum availability
```
の場合には、以下のようにして、ノード数を増やしてみる(課金増える)が、実は、imageを取れてないだけだったりとかもする。
```
gcloud container clusters resize rails-on-k8s --size=3
```



---
