# rails-on-k8s
## Purpose
以下を目指す

- [x] 第一段階 : Railsアプリをminikubeで動かせる(hello yay)
- [ ] 第二段階 : Railsアプリのコードベースを変更したら、それがminikube上で反映されていることが確認できる
- [ ] 第三段階 : RailsアプリをGKEにデプロイして公開できる
- [ ] 第四段階 : RailsアプリのIPを固定化し、domainを与え、https化する
- [ ] 第五段階 : GitOps式のCICD pipeline を実現する

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

動作確認(この時点ではDB connection errorでよい)
```
docker run  -p 0.0.0.0:3000:3000 --rm rails-on-k8s bundle exec rails server -p 3000 -b 0.0.0.0
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


---
