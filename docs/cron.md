# Cron設定ガイド

## 3ヶ月ごとのバックアップ設定

### 推奨設定

1,4,7,10月の第1日曜日 深夜2時に実行:

```bash
0 2 1-7 1,4,7,10 * [ $(date +\%w) -eq 0 ] && curl -s https://raw.githubusercontent.com/{YOUR_GITHUB_USER}/synology-s3-backup/main/scripts/backup.sh | bash -s -- backup
```

### 設定方法

1. SSHでNASに接続:
```bash
ssh admin@nas-ip-address
```

2. crontabを編集:
```bash
crontab -e
```

3. 上記のcron設定を追加

4. 保存して終了

### その他のスケジュール例

**毎月1日の深夜3時**
```bash
0 3 1 * * curl -s https://raw.githubusercontent.com/{YOUR_GITHUB_USER}/synology-s3-backup/main/scripts/backup.sh | bash -s -- backup
```

**毎週日曜日の深夜2時**
```bash
0 2 * * 0 curl -s https://raw.githubusercontent.com/{YOUR_GITHUB_USER}/synology-s3-backup/main/scripts/backup.sh | bash -s -- backup
```

**2ヶ月ごと (奇数月の1日)**
```bash
0 2 1 1,3,5,7,9,11 * curl -s https://raw.githubusercontent.com/{YOUR_GITHUB_USER}/synology-s3-backup/main/scripts/backup.sh | bash -s -- backup
```

### 注意事項

- `{YOUR_GITHUB_USER}`を実際のGitHubユーザー名に置き換えてください
- NASの電源が入っている時間帯を選択してください
- ログは `/volume1/backup-config/logs/` に保存されます
- cron実行時はメール通知が送信される場合があります

### 動作確認

設定したcronジョブの確認:
```bash
crontab -l
```

次回実行予定の確認 (Synology DSM):
- コントロールパネル → タスクスケジューラー