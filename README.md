# Synology S3 Backup

Synology NASの`/var/services/homes`をAWS S3 Glacier Deep Archiveに定期バックアップするスクリプト。

## 使い方

### 初期設定
```bash
curl -s https://raw.githubusercontent.com/{GITHUB_REPO}/main/scripts/backup.sh | bash -s -- init
```

### バックアップ実行
```bash
curl -s https://raw.githubusercontent.com/{GITHUB_REPO}/main/scripts/backup.sh | bash -s -- backup
```

### リストア
```bash
curl -s https://raw.githubusercontent.com/{GITHUB_REPO}/main/scripts/backup.sh | bash -s -- restore [YYYYMMDD-HHMMSS]
```

## セットアップ

詳細は[docs/setup.md](docs/setup.md)を参照。

## Cron設定

3ヶ月ごとの自動実行については[docs/cron.md](docs/cron.md)を参照。