# Synology NAS バックアップスクリプト設計書

## プロジェクト概要
Synology NASの`/var/services/homes`（約2TB）をAWS S3 Glacier Deep Archiveに定期バックアップするスクリプト。GitHubで管理し、cronから動的に取得・実行する。

## システム要件
- **実行環境**: Synology NAS（gitコマンドなし）
- **Docker**: `/usr/local/bin/docker`
- **コンテナ**: `amazon/aws-cli`
- **バックアップ頻度**: 3ヶ月ごと
- **保存期間**: 180日（自動削除）

## ディレクトリ構成

### GitHubリポジトリ（公開）
```
synology-nas-backup/
├── README.md
├── scripts/
│   └── backup.sh            # メインスクリプト
├── config/
│   └── backup.conf.example  # 設定ファイルサンプル
└── docs/
    ├── setup.md            # セットアップガイド
    └── cron.md             # cron設定例
```

### Synology NAS
```
/volume1/backup-config/
├── backup.conf             # 設定ファイル（パーミッション600）
└── logs/
    └── backup-YYYYMMDD-HHMMSS.log
```

## コマンド仕様

### 1. init - 初期設定
```bash
curl -s https://raw.githubusercontent.com/{GITHUB_REPO}/production/scripts/backup.sh | bash -s -- init
```
**機能**:
- 設定ファイル作成/更新（対話式）
- AWS認証情報設定
- S3バケット作成（Glacier Deep Archive）
- ライフサイクルルール設定（180日自動削除）
- 圧縮性能テスト（レベル1/6/9で2TB推定時間表示）
- すべて冪等性を保証

### 2. backup - バックアップ実行
```bash
curl -s https://raw.githubusercontent.com/{GITHUB_REPO}/production/scripts/backup.sh | bash -s -- backup
```
**処理フロー**:
1. 自動検証（verify）
   - 設定ファイル確認
   - AWS接続確認
   - S3アクセス確認
   - エラー時は即終了
2. バックアップ実行
   - 空き容量確認（最低1.5TB）
   - tar.gz圧縮（レベル設定可能）
   - S3マルチパートアップロード
   - ファイル名: `backup-YYYYMMDD-HHMMSS.tar.gz`

### 3. restore - リストア
```bash
curl -s https://raw.githubusercontent.com/{GITHUB_REPO}/production/scripts/backup.sh | bash -s -- restore [YYYYMMDD-HHMMSS]
```
**機能**:
- バックアップ一覧表示
- Glacier復元ジョブ開始（12-48時間）
- ダウンロード・展開（デフォルト: `/volume1/restore/`）

## 設定ファイル仕様（backup.conf）
```bash
# AWS設定
AWS_PROFILE="nas-backup"
AWS_REGION="ap-northeast-1"
S3_BUCKET="my-nas-backup-bucket"
S3_PREFIX="synology-backup"

# バックアップ設定
BACKUP_SOURCE="/var/services/homes"
TEMP_DIR="/volume1/backup-temp"
LOG_DIR="/volume1/backup-config/logs"
LOG_RETENTION_DAYS=30
COMPRESSION_LEVEL="6"        # 1-9
MIN_FREE_SPACE_GB="1500"

# GitHub設定
GITHUB_REPO="username/synology-nas-backup"
SCRIPT_PATH="scripts/backup.sh"
```

## 実装詳細

### AWS CLI実行方法
```bash
docker run --rm \
    -v ~/.aws:/root/.aws:ro \
    -v /volume1:/volume1 \
    amazon/aws-cli s3 cp file.tar.gz s3://${S3_BUCKET}/${S3_PREFIX}/
```

### ライフサイクルルール
```json
{
  "Rules": [{
    "ID": "synology-backup-auto-delete",
    "Status": "Enabled",
    "Filter": {"Prefix": "synology-backup/"},
    "Transitions": [{"Days": 0, "StorageClass": "DEEP_ARCHIVE"}],
    "Expiration": {"Days": 180}
  }]
}
```

### エラーハンドリング
- 致命的エラー: `exit 1`
- AWS APIエラー: 3回リトライ
- ログ記録: すべての処理を記録

## セキュリティ設計

### IAMポリシー（最小権限）
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:DeleteObject",
        "s3:PutBucketLifecycleConfiguration",
        "s3:GetBucketLifecycleConfiguration"
      ],
      "Resource": [
        "arn:aws:s3:::my-nas-backup-bucket",
        "arn:aws:s3:::my-nas-backup-bucket/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:RestoreObject"],
      "Resource": "arn:aws:s3:::my-nas-backup-bucket/*"
    }
  ]
}
```

### 認証情報管理
- 保存先: `~/.aws/credentials`
- プロファイル名: `nas-backup`
- 設定ファイル: パーミッション600

## ドキュメント構成

### docs/setup.md
1. AWS IAMユーザー作成手順
2. 初期設定コマンド実行手順
3. 動作確認方法
4. トラブルシューティング

### docs/cron.md
```bash
# 3ヶ月ごとの実行例（1,4,7,10月の第1日曜日 深夜2時）
0 2 1-7 1,4,7,10 * [ $(date +\%w) -eq 0 ] && curl -s https://raw.githubusercontent.com/{GITHUB_REPO}/production/scripts/backup.sh | bash -s -- backup
```

## 実装時の注意事項
1. すべての操作は冪等性を保証
2. 公開リポジトリのため認証情報は含めない
3. 圧縮は一時的に最大1TBの空き容量が必要
4. Glacier Deep Archiveは取り出しに12-48時間必要
