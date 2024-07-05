# ベースイメージとして Dart SDK を使用
FROM dart:stable

# 作業ディレクトリを設定
WORKDIR /app

# 必要なファイルをコピー
COPY . .

# 依存関係を取得
RUN dart pub get

# アプリケーションを実行
CMD ["dart", "example/example.dart"]