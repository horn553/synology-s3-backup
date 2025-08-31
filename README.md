# Synology S3 Backup

Synology NAS の`/var/services/homes`を AWS S3 Glacier Deep Archive に定期バックアップするスクリプト。

## 使い方

### 初期設定

```bash
curl -s https://raw.githubusercontent.com/horn553/synology-s3-backup/main/scripts/backup.sh | bash -s -- init
```

### バックアップ実行

```bash
curl -s https://raw.githubusercontent.com/horn553/synology-s3-backup/main/scripts/backup.sh | bash -s -- backup
```

### リストア

```bash
curl -s https://raw.githubusercontent.com/horn553/synology-s3-backup/main/scripts/backup.sh | bash -s -- restore [YYYYMMDD-HHMMSS]
```

## セットアップ

詳細は[docs/setup.md](docs/setup.md)を参照。

## Cron 設定

3 ヶ月ごとの自動実行については[docs/cron.md](docs/cron.md)を参照。
