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


## Usage
1. Dockerfileをビルドして、rails gem入りのDocker Imageを作る
```
docker build . -t rails-on-k8s
```

2. Docker Image を runして、 bundle exec rails new する
(makeコマンド, databaseは？)
docker exec rails new --database=mysql --skip-test

3. Minikubeで動かせるように、deploymentなどを用意する
- secret
- pvc
- deployment
- service
