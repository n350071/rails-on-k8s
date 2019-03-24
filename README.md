# rails-on-k8s
## Purpose
以下を目指す

- 第一段階
  - Railsアプリをminikubeで動かせる(hello yay)
    - [nao0515ki/docker-for-rails](https://github.com/nao0515ki/docker-for-rails)を応用して、ralis newした状態のものを用意しよう(そもそも docker-composeじゃないしね)
      - k8s-for-rails リポジトリを作ってもいいかもしれない
    - deploymentのimageはどうしよう？
      - コードをdocker buildして、それを使う感じかな？
        - ローカルのimageをpullして使ってくれるかな？
        - 開発環境では、skaffoldを使うといいとか..
    - postgressのところは、mysqlに置き換える
    - mysqlへの接続情報のところは、pvcなどを使っていい感じにする
- 第二段階
  - Railsアプリのコードベースを変更したら、それがminikube上で反映されていることが確認できる
- 第三段階
  - RailsアプリをGKEにデプロイして公開できる
    - 基本的には、プロジェクトを作って、クラスタを作ったら..
    - あとは同じkubectlコマンドで済むはず
- 第四段階
  - RailsアプリのIPを固定化し、domainを与え、https化する
  - 手順をメモしておいて、すぐに再現できるようにする
- 第五段階
  - GitOps式のCICD pipeline を実現する
  - この段階まで、リポジトリ内にマニフェストが混在していてもいい


## 実行
### 第一段階
1. Dockerfileをビルドして、rails gem入りのDocker Imageを作る
```
docker build . -t rails-on-k8s
```

2. Docker Image を runして、 bundle exec rails new する

```
docker run --rm -v $PWD:$PWD -w $PWD rails-on-k8s bundle exec rails new . --database=mysql --skip-test
```

参考になった記事
[Dockerコンテナからホスト側カレントディレクトリにアクセス](https://qiita.com/yoichiwo7/items/ce2ade791462b4f50cf3)
- --rmオプションでDockerコンテナのプロセス(コマンド)が終了した時点でコンテナを破棄します。コマンド終了後にDockerコンテナ上のファイルを色々とアクセスしたい場合は外しても構いません。
- --userオプションでホスト側のUIDを指定します。指定しない場合、生成したファイル等の所有者がroot:rootとなるためホスト側のユーザが編集したり削除したりできません。
- -v $PWD:$PWDオプションで、ホスト側カレントディレクトリとコンテナ側カレントディレクトリのボリューム内容を一致させます。
- -w $PWDオプションで、ホスト側カレントディレクトリとコンテナ側カレントディレクトリのディレクトリパスを一致させます。-v $PWD:$PWDオプションと組み合わせて使います。


動作確認
```
docker run  -p 0.0.0.0:3000:3000 --rm rails-on-k8s bundle exec rails server -p 3000 -b 0.0.0.0
```

3. Minikubeで動かせるように、deploymentなどを用意する
- secret
- pvc
- deployment
- service

まずはクラスタの作成
```
minikube start
```

こんな感じでできるようにしたい
```
kubectl create secret generic mysql-pass --from-literal=password=mysqlpass
kubectl apply -f k8s-mysql.yaml
kubectl apply -f k8s-rails.yaml
kubectl get pvc
kubectl get deployments
kubectl get pods
kubectl get services
minikube service rails --url
```

**イメージのプルができてない..**
```
$ kubectl describe pod rails

Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  41s                default-scheduler  Successfully assigned default/rails-6f7b84dd5b-52tnk to minikube
  Normal   BackOff    33s                kubelet, minikube  Back-off pulling image "rails-on-k8s:latest"
  Warning  Failed     33s                kubelet, minikube  Error: ImagePullBackOff
  Normal   Pulling    20s (x2 over 40s)  kubelet, minikube  pulling image "rails-on-k8s:latest"
  Warning  Failed     9s (x2 over 33s)   kubelet, minikube  Failed to pull image "rails-on-k8s:latest": rpc error: code = Unknown desc = Error response from daemon: pull access denied for rails-on-k8s, repository does not exist or may require 'docker login'
  Warning  Failed     9s (x2 over 33s)   kubelet, minikube  Error: ErrImagePull
  ```

[Reusing the Docker daemon](https://github.com/kubernetes/minikube/blob/0c616a6b42b28a1aab8397f5a9061f8ebbd9f3d9/README.md#reusing-the-docker-daemon) をすると、Docker deamonを再利用することができて、つまり、イメージをbuild,pushする必要なく、同じdocker deamonの中でbuildできるから、ローカル開発のスピードアップになる..
```
eval $(minikube docker-env)
docker build . -t rails-on-k8s
kubectl delete pods -l app=rails
kubectl get pods
```

**イメージのpullはできたが、CrashLoopBackOffが発生。**

コンテナが起動しては、終了して、、繰り返しているのかもしれない。。
Dockerfileの最下部へ `CMD ["bundle", "exec", "rails", "s", "-p", "3000", "-b", "0.0.0.0"]`を追加したら動いた!!
```
$kubectl get pods
NAME                     READY   STATUS    RESTARTS   AGE
mysql-8586c575dd-5bhzt   1/1     Running   0          7m11s
rails-79b8cf8d55-zwnpv   1/1     Running   0          14s
```

サービスの外部公開が失敗している...
原因はわからないが、いくつかの実験から、 `eval $(minikube docker-env)` に原因があることがわかった。
よって、この方法は使えない..

`skaffold`をつかってみよう
- [参考記事](https://qiita.com/tomoyamachi/items/660bd7bb3afff8340307#skaffold%E3%81%AB%E3%81%A4%E3%81%84%E3%81%A6)
- [Skaffold Documentation](https://skaffold.dev/docs/)

[Getting Started](https://skaffold.dev/docs/getting-started/)
- [Reference cli dev](https://skaffold.dev/docs/references/cli/#skaffold-dev)
- [skaffold.yaml](https://skaffold.dev/docs/references/yaml/)
[skaffold.yaml](https://github.com/GoogleContainerTools/skaffold/blob/master/examples/getting-started/skaffold.yaml)を設置、imageを書き換え。
```
brew install skaffold
skaffold dev --cache-artifacts
```
--cache-artifacts : キャッシュする

イメージのpull問題は解決した
```
Container image "rails-on-k8s:e5f7b687cfef997e29015eb5a03a6ff91d16a3b5ecc882ebde3a01d3e34db439" already present on machine
```

**puma落ちてる..!?**
→ポート番号が合ってないだけだった。
```
deployment.apps/rails configured
Deploy complete in 573.57329ms
Watching for changes every 1s...
[rails-7454c58698-kpj76 rails] => Booting Puma
[rails-7454c58698-kpj76 rails] => Rails 5.2.2.1 application starting in development
[rails-7454c58698-kpj76 rails] => Run `rails server -h` for more startup options
[rails-7454c58698-kpj76 rails] Puma starting in single mode...
[rails-7454c58698-kpj76 rails] * Version 3.12.1 (ruby 2.5.5-p157), codename: Llamas in Pajamas
[rails-7454c58698-kpj76 rails] * Min threads: 5, max threads: 5
[rails-7454c58698-kpj76 rails] * Environment: development
[rails-7454c58698-kpj76 rails] * Listening on tcp://0.0.0.0:3000
[rails-7454c58698-kpj76 rails] Use Ctrl-C to stop
[rails-7454c58698-kpj76 rails] - Gracefully stopping, waiting for requests to finish
[rails-7454c58698-kpj76 rails] === puma shutdown: 2019-03-24 03:27:44 +0000 ===
[rails-7454c58698-kpj76 rails] - Goodbye!
[rails-7454c58698-kpj76 rails] Exiting
Port Forwarding rails-679bf9b89c-rcl26/rails 3000 -> 3000
```

ログインして見てみると、そうでもない..
```
$kubectl get pod
NAME                               READY   STATUS    RESTARTS   AGE
rails-679bf9b89c-rcl26             1/1     Running   0          2m26s
$kubectl exec -it rails-679bf9b89c-rcl26 /bin/bash

$kubectl exec -it rails-679bf9b89c-rcl26 /bin/bash

root@rails-679bf9b89c-rcl26:/myapp#bundle exec rails s
=> Booting Puma
=> Rails 5.2.2.1 application starting in development
=> Run `rails server -h` for more startup options
A server is already running. Check /myapp/tmp/pids/server.pid.
Exiting

root@rails-679bf9b89c-rcl26:/myapp# ps aux | grep puma
root         1  0.3  2.9 1142908 59432 ?       Ssl  03:27   0:02 puma 3.12.1 (tcp://0.0.0.0:3000) [myapp]

root@rails-679bf9b89c-rcl26:/myapp# ls -l /proc/1/cwd
lrwxrwxrwx. 1 root root 0 Mar 24 03:41 /proc/1/cwd -> /myapp

root@rails-679bf9b89c-rcl26:/myapp# cat /proc/1/cmdline
puma 3.12.1 (tcp://0.0.0.0:3000) [myapp]
```

Deploymentや、Servieseのポートとかが合ってない？
Dockerfileの `EXPOSE 3000` に合わせてみたら、見れるようになった。
```
Service.spec.ports.port: 3000
Deployment.spec.template.spec.containers.ports.containerPort: 3000
```

**Mysql2::Error::ConnectionError**
Railsのconfig/database.ymlの、hostがlocalhostになっていた。
これを、mysqlに修正。kubernetesのサービスでは、ラベルを利用したpodのサービスディスカバリがあるので、これで解決できる。
```
host: mysql
```

**Unknown database 'rails-on-k8s_development'**
mysqlが存在してない時点で、rails newしたのが原因かもしれない..
kubernetesの中に入り、 `db:create` をしたら解決した。
```
$kubectl exec -it rails-7c5554945c-j8rh9 /bin/bash
root@rails-7c5554945c-j8rh9:/myapp# bundle exec rails db:create
Created database 'rails-on-k8s_development'
Created database 'rails-on-k8s_test'
```

















#### 手順のリファクタリング
### 第一段階
#### 1. [skaffold](https://skaffold.dev/docs/)を利用する

##### 概要
skaffoldは、kubernetesに対して、Google製のビルド〜デプロイまでを行ってくれるコマンドラインツール。
開発環境において、ビルドしたイメージをレジストリにアップせずに、直接kubernetesのpodに入れてくれる。
よって、`docker build . -t <IMAGE_NAME>:<VERSION>`のような作業や、dockerへのpushなどが不要になる。

##### インストール
```
brew install skaffold
```

##### 使い方
1. [skaffold.yaml](https://github.com/GoogleContainerTools/skaffold/blob/master/examples/getting-started/skaffold.yaml)を設置、build.artifacts.imageを、任意の<IMAGE_NAME>に書き換える。
2. `skaffold dev --cache-artifacts` を実行
--cache-artifacts : キャッシュする ($HOME/.skaffold/cache)
これで、ローカルで変更があるたびに、kubernetesの<IMAGE_NAME>を使うpod内のcontainerが置き換わる。

##### 詳細
- [Reference cli dev](https://skaffold.dev/docs/references/cli/#skaffold-dev)
- [skaffold.yaml](https://skaffold.dev/docs/references/yaml/)
- [参考記事](https://qiita.com/tomoyamachi/items/660bd7bb3afff8340307#skaffold%E3%81%AB%E3%81%A4%E3%81%84%E3%81%A6)

#### 2. Minikubeを起動して、リソースを配置する

##### クラスタを作成し、順次実行する
クラスタ作成 (必要なら、`minikube delete`してからでもいいかも.. )
```
minikube start
```

リソース配置
```
kubectl create secret generic mysql-pass --from-literal=password=<PASSWORD>
kubectl apply -f k8s-mysql.yaml
kubectl apply -f k8s-rails.yaml
```

リソース確認
```
kubectl get pvc
kubectl get deployments
kubectl get pods
kubectl get services
```

minikubeから、rails serviceに対して、EXTERNAL-IPを与える(その後に`kubectl get services`をしても出てこないが..)
```
minikube service rails --url
```
なお、 `minikube service rails`でブラウザが開く。

#### 3. Rails newする

まず、podの名前を確認する
```
kubectl get pods
```

railsのpodに対して、rails newを行う
```
kubectl exec <POD_NAME> bundle exec rails new . --database=mysql --skip-test

```

↓不要かな？
#### db:create
```
$kubectl exec -it rails-7c5554945c-j8rh9 /bin/bash
root@rails-7c5554945c-j8rh9:/myapp# bundle exec rails db:create
Created database 'rails-on-k8s_development'
Created database 'rails-on-k8s_test'
```


---
Docker Image を runして、 bundle exec rails new する

```
docker run --rm -v $PWD:$PWD -w $PWD rails-on-k8s bundle exec rails new . --database=mysql --skip-test
```

参考になった記事
[Dockerコンテナからホスト側カレントディレクトリにアクセス](https://qiita.com/yoichiwo7/items/ce2ade791462b4f50cf3)
- --rmオプションでDockerコンテナのプロセス(コマンド)が終了した時点でコンテナを破棄します。コマンド終了後にDockerコンテナ上のファイルを色々とアクセスしたい場合は外しても構いません。
- --userオプションでホスト側のUIDを指定します。指定しない場合、生成したファイル等の所有者がroot:rootとなるためホスト側のユーザが編集したり削除したりできません。
- -v $PWD:$PWDオプションで、ホスト側カレントディレクトリとコンテナ側カレントディレクトリのボリューム内容を一致させます。
- -w $PWDオプションで、ホスト側カレントディレクトリとコンテナ側カレントディレクトリのディレクトリパスを一致させます。-v $PWD:$PWDオプションと組み合わせて使います。


動作確認
```
docker run  -p 0.0.0.0:3000:3000 --rm rails-on-k8s bundle exec rails server -p 3000 -b 0.0.0.0
```






### 第二段階


---
