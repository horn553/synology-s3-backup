# Synology S3 Backup セットアップガイド

## 前提条件

- Synology NAS (Docker対応モデル)
- AWSアカウント
- インターネット接続
- 空き容量: 最低1.5TB (バックアップ一時保存用)

## 1. AWSアカウントの準備

### 1.1 IAMユーザーの作成

1. AWS Management Consoleにログイン
2. IAMサービスに移動
3. 「ユーザー」→「ユーザーの追加」をクリック
4. ユーザー名: `synology-backup` を入力
5. アクセスの種類: 「プログラムによるアクセス」を選択
6. 次へ進む

### 1.2 IAMポリシーの作成

1. 「ポリシーの作成」をクリック
2. JSONタブを選択し、以下を貼り付け:

```json
{
	"Version": "2012-10-17",
	"Statement": [
		{
			"Sid": "VisualEditor0",
			"Effect": "Allow",
			"Action": [
				"s3:GetLifecycleConfiguration",
				"s3:PutLifecycleConfiguration",
				"s3:CreateBucket",
				"s3:ListBucket"
			],
			"Resource": "arn:aws:s3:::*-nas-backup-*"
		},
		{
			"Sid": "VisualEditor1",
			"Effect": "Allow",
			"Action": [
				"s3:PutObject",
				"s3:GetObject",
				"s3:DeleteObject"
			],
			"Resource": "arn:aws:s3:::*-nas-backup-*/*"
		},
		{
			"Sid": "VisualEditor2",
			"Effect": "Allow",
			"Action": "s3:RestoreObject",
			"Resource": "arn:aws:s3:::*-nas-backup-*/*"
		},
		{
			"Sid": "VisualEditor3",
			"Effect": "Allow",
			"Action": "s3:ListAllMyBuckets",
			"Resource": "*"
		}
	]
}
```

3. ポリシー名: `SynologyBackupPolicy`
4. 作成したポリシーをユーザーにアタッチ
5. アクセスキーIDとシークレットアクセスキーを安全に保存

## 2. Synology NASでの初期設定

### 2.1 SSHでNASに接続

```bash
ssh admin@nas-ip-address
```

### 2.2 初期設定スクリプトの実行

```bash
curl -s https://raw.githubusercontent.com/{YOUR_GITHUB_USER}/synology-s3-backup/main/scripts/backup.sh | bash -s -- init
```

実行すると以下を対話的に設定:

1. AWS認証情報の入力
   - Access Key ID
   - Secret Access Key

2. S3バケット名の入力
   - 例: `my-nas-backup-20240101`
   - グローバルに一意である必要があります

3. 圧縮性能テストの実行
   - レベル1, 6, 9での圧縮時間を測定
   - 2TB推定時間を表示

### 2.3 設定ファイルの確認・編集

必要に応じて設定を調整:

```bash
vi /volume1/backup-config/backup.conf
```

主な設定項目:
- `GITHUB_REPO`: あなたのGitHubリポジトリに変更
- `COMPRESSION_LEVEL`: 圧縮レベル (1-9)
- `MIN_FREE_SPACE_GB`: 最小空き容量 (GB)

## 3. 動作確認

### 3.1 小規模テストバックアップ

テスト用ディレクトリを作成してバックアップ:

```bash
# テストディレクトリ作成
mkdir -p /volume1/test-backup
echo "test file" > /volume1/test-backup/test.txt

# 設定を一時的に変更
cp /volume1/backup-config/backup.conf /volume1/backup-config/backup.conf.bak
sed -i 's|BACKUP_SOURCE=.*|BACKUP_SOURCE="/volume1/test-backup"|' /volume1/backup-config/backup.conf

# テストバックアップ実行
curl -s https://raw.githubusercontent.com/{YOUR_GITHUB_USER}/synology-s3-backup/main/scripts/backup.sh | bash -s -- backup

# 設定を戻す
mv /volume1/backup-config/backup.conf.bak /volume1/backup-config/backup.conf
```

### 3.2 S3での確認

AWSコンソールまたはCLIで確認:

```bash
docker run --rm -v ~/.aws:/root/.aws:ro -e AWS_PROFILE=nas-backup amazon/aws-cli s3 ls s3://your-bucket-name/synology-backup/
```

## 4. Cron設定

3ヶ月ごとの自動実行を設定:

```bash
# crontabを編集
crontab -e

# 以下を追加 (1,4,7,10月の第1日曜日 深夜2時)
0 2 1-7 1,4,7,10 * [ $(date +\%w) -eq 0 ] && curl -s https://raw.githubusercontent.com/{YOUR_GITHUB_USER}/synology-s3-backup/main/scripts/backup.sh | bash -s -- backup
```

## 5. トラブルシューティング

### ログの確認

```bash
ls -la /volume1/backup-config/logs/
tail -f /volume1/backup-config/logs/backup-*.log
```

### よくある問題

**Docker not found**
- パッケージセンターからDockerをインストール

**Permission denied**
- sudoを使用するか、管理者権限で実行

**AWS authentication failed**
- 認証情報を再確認: `~/.aws/credentials`

**Insufficient space**
- `/volume1`の空き容量を確認
- `TEMP_DIR`を別のボリュームに変更

**S3 access denied**
- IAMポリシーを確認
- バケット名のパターンが一致しているか確認

### サポート

問題が解決しない場合は、GitHubのIssueで報告してください。
