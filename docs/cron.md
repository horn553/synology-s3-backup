# Cron 設定ガイド

## 3 ヶ月ごとのバックアップ設定

### 推奨設定

1,4,7,10 月の第 1 日曜日 深夜 2 時に実行:

```bash
0 2 1-7 1,4,7,10 * [ $(date +\%w) -eq 0 ] && curl -s https://raw.githubusercontent.com/horn553/synology-s3-backup/main/scripts/backup.sh | bash -s -- backup
```

### 設定方法

1. SSH で NAS に接続:

```bash
ssh admin@nas-ip-address
```

2. crontab を編集:

```bash
crontab -e
```

3. 上記の cron 設定を追加

4. 保存して終了

### その他のスケジュール例

**毎月 1 日の深夜 3 時**

```bash
0 3 1 * * curl -s https://raw.githubusercontent.com/horn553/synology-s3-backup/main/scripts/backup.sh | bash -s -- backup
```

**毎週日曜日の深夜 2 時**

```bash
0 2 * * 0 curl -s https://raw.githubusercontent.com/horn553/synology-s3-backup/main/scripts/backup.sh | bash -s -- backup
```

**2 ヶ月ごと (奇数月の 1 日)**

```bash
0 2 1 1,3,5,7,9,11 * curl -s https://raw.githubusercontent.com/horn553/synology-s3-backup/main/scripts/backup.sh | bash -s -- backup
```

### 注意事項

- `horn553`を実際の GitHub ユーザー名に置き換えてください
- NAS の電源が入っている時間帯を選択してください
- ログは `/volume1/backup-config/logs/` に保存されます
- cron 実行時はメール通知が送信される場合があります

### 動作確認

設定した cron ジョブの確認:

```bash
crontab -l
```

次回実行予定の確認 (Synology DSM):

- コントロールパネル → タスクスケジューラー
