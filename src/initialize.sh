#!/bin/bash
# ---------------------------------
# EC2 user data
# Autoscaling startup scripts.
# ---------------------------------
# 変数の定義
APP_NAME="laravel-app"
ENVIRONMENT="dev"
REGION="ap-northeast-1"
DOMAIN="cloud-app-lab.com"
S3_BUCKET="s3.cloud-app-lab.com"
S3_PATH="storage"

#パッケージインストール
sudo yum install nginx -y
sudo yum install git -y
sudo yum install php8.3-fpm -y
sudo yum install php8.3 -y
sudo yum install unzip -y

#ログ設定
LOGFILE="/var/log/initialize.log"
exec > "${LOGFILE}"
exec 2>&1

#SSMパラメータ取得
MYSQL_HOST=$(aws ssm get-parameter --name "/${APP_NAME}/${ENVIRONMENT}/app/MYSQL_HOST" --region ${REGION} --query "Parameter.Value" --output text)
MYSQL_DATABASE=$(aws ssm get-parameter --name "/${APP_NAME}/${ENVIRONMENT}/app/MYSQL_DATABASE" --region ${REGION} --with-decryption --query "Parameter.Value" --output text)
MYSQL_USERNAME=$(aws ssm get-parameter --name "/${APP_NAME}/${ENVIRONMENT}/app/MYSQL_USERNAME" --region ${REGION} --with-decryption --query "Parameter.Value" --output text)
MYSQL_PASSWORD=$(aws ssm get-parameter --name "/${APP_NAME}/${ENVIRONMENT}/app/MYSQL_PASSWORD" --region ${REGION} --with-decryption --query "Parameter.Value" --output text)
S3_ACCESS_KEY_ID=$(aws ssm get-parameter --name "/${APP_NAME}/${ENVIRONMENT}/app/S3_ACCESS_KEY_ID" --region ${REGION} --with-decryption --query "Parameter.Value" --output text)
S3_SECRET_ACCESS_KEY=$(aws ssm get-parameter --name "/${APP_NAME}/${ENVIRONMENT}/app/S3_SECRET_ACCESS_KEY" --region ${REGION} --with-decryption --query "Parameter.Value" --output text)
GITHUB_PAT_TOKEN=$(aws ssm get-parameter --name "/laravel-app/dev/app/GITHUB_PAT_TOKEN" --region "ap-northeast-1" --query "Parameter.Value" --with-decryption --output text)

#GitHubクローン
sudo chmod 777 /var/www
git clone https://$GITHUB_PAT_TOKEN@github.com/registnotes/laravel-app.git /var/www/laravel-app
cd /var/www/laravel-app
sudo php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
sudo php composer-setup.php --filename=composer
sudo chown -R nginx:nginx /var/www/laravel-app
sudo chmod -R 755 /var/www/laravel-app

#S3にLaravelシード用ファイルを差分アップロード
aws s3 sync /var/www/laravel-app/storage/app/public s3://$S3_BUCKET/$S3_PATH --exact-timestamps

#PHP fpm設定
CONFIG_FILE="/etc/php-fpm.d/www.conf"
sudo sed -i 's/^user = apache/user = nginx/' $CONFIG_FILE
sudo sed -i 's/^group = apache/group = nginx/' $CONFIG_FILE
sudo sed -i 's/^listen = \/run\/php-fpm\/www.sock/listen = 127.0.0.1:9000/' $CONFIG_FILE
sudo rm /etc/php.d/10-opcache.ini
sudo systemctl restart php-fpm

#Nginx設定
NGINX_CONF="/etc/nginx/conf.d/laravel.conf"
PUBLIC_IP=$(ec2-metadata | sed -n 's/^public-ipv4: //p')
sudo tee "$NGINX_CONF" > /dev/null <<EOF
server {
    listen 3000;
    server_name XXX.XXX.XXX.XXX;

    root /var/www/laravel-app/public;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_index index.php;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
sudo sed -i "s/XXX.XXX.XXX.XXX/$PUBLIC_IP/" $NGINX_CONF
sudo systemctl restart nginx

#MySQLインストール
sudo dnf -y install https://dev.mysql.com/get/mysql84-community-release-el9-1.noarch.rpm
sudo dnf -y install mysql mysql-community-client
sudo dnf -y install mysql-community-server
sudo dnf install -y php-mysqlnd
sudo systemctl enable mysqld.service
sudo systemctl start mysqld.service
#sudo systemctl status mysqld.service

#Laravelインストール
sudo chown -R ec2-user:ec2-user /var/www
sudo chmod -R 2775 /var/www
sudo usermod -a -G nginx ec2-user
cd /var/www/laravel-app
sudo ln -s /var/www/laravel-app/composer /usr/local/bin/composer
sudo git config --global --add safe.directory /var/www/laravel-app
sudo COMPOSER_ALLOW_SUPERUSER=1 composer install --optimize-autoloader --no-dev
sudo COMPOSER_ALLOW_SUPERUSER=1 composer update

# .envファイルを置換
cp .env.example .env
sed -i "s/^DB_CONNECTION=.*/DB_CONNECTION=mysql/" .env
sed -i "s/^# DB_HOST=.*/DB_HOST=${MYSQL_HOST}/" .env
sed -i "s/^# DB_DATABASE=.*/DB_DATABASE=${MYSQL_DATABASE}/" .env
sed -i "s/^# DB_PORT=.*/DB_PORT=3306/" .env
sed -i "s/^# DB_USERNAME=.*/DB_USERNAME=${MYSQL_USERNAME}/" .env
sed -i "s/^# DB_PASSWORD=.*/DB_PASSWORD=${MYSQL_PASSWORD}/" .env
sed -i "s/^SESSION_DRIVER=.*/SESSION_DRIVER=file/" .env
sed -i "s/^APP_LOCALE=.*/APP_LOCALE=ja/" .env
sed -i "s/^APP_FALLBACK_LOCALE=.*/APP_FALLBACK_LOCALE=ja/" .env
sed -i "s/^APP_FAKER_LOCALE=.*/APP_FAKER_LOCALE=ja_JP/" .env
sed -i "s/^APP_ENV=.*/APP_ENV=production/" .env
sed -i "s/^CACHE_STORE=.*/CACHE_STORE=file/" .env
sed -i "/^SESSION_DOMAIN=null/a SESSION_SECURE_COOKIE=true" .env #新規行を追加して
sed -i "s/^APP_DEBUG=.*/APP_DEBUG=false/" .env
sed -i "s/^AWS_ACCESS_KEY_ID=.*/AWS_ACCESS_KEY_ID=${S3_ACCESS_KEY_ID}/" .env
sed -i "s/^AWS_SECRET_ACCESS_KEY=.*/AWS_SECRET_ACCESS_KEY=${S3_SECRET_ACCESS_KEY}/" .env
sed -i "s/^AWS_DEFAULT_REGION=.*/AWS_DEFAULT_REGION=${REGION}/" .env
sed -i "s/^AWS_BUCKET=.*/AWS_BUCKET=${S3_BUCKET}/" .env
sed -i "s/^AWS_USE_PATH_STYLE_ENDPOINT=.*/AWS_USE_PATH_STYLE_ENDPOINT=false/" .env

#マイグレーション
#sudo php artisan key:generate --force
#sudo php artisan migrate --force
#sudo php artisan migrate:refresh --seed --force
sudo php artisan key:generate --no-interaction
# MySQL 認証情報を含む mysql.cnf を作成
cat <<EOF > mysql.cnf
[client]
host = ${MYSQL_HOST}
user = ${MYSQL_USERNAME}
password = ${MYSQL_PASSWORD}
database = ${MYSQL_DATABASE}
EOF
# ユーザーテーブルの存在を確認
TABLE_EXISTS=$(mysql --defaults-extra-file=mysql.cnf -N -e "SHOW TABLES LIKE 'users';")
echo "TABLE_EXISTS: $TABLE_EXISTS"
# テーブルが存在しない場合はマイグレーションとシードを実行
if [ -z "$TABLE_EXISTS" ]; then
    echo "usersテーブルが存在しません。マイグレーションを実行します..."
    cd /var/www/laravel-app
    sudo php artisan migrate --force
    sudo php artisan migrate:refresh --seed --force
    echo "Database seed completed."
else
    USER_COUNT=$(mysql --defaults-extra-file=mysql.cnf -N -e "SELECT COUNT(*) FROM users;")
    if [ "$USER_COUNT" -eq 0 ]; then
        echo "USER_COUNT: $USER_COUNT"
        echo "usersテーブルのデータ数が0です。マイグレーションを実行します..."
        cd /var/www/laravel-app
        sudo php artisan migrate --force
        sudo php artisan migrate:refresh --seed --force
        echo "Database seed completed."
    fi
fi
rm -f "$MYSQL_CNF"
sudo dnf remove nodejs -y
sudo curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
sudo dnf install -y nodejs
sudo npm install
sudo npm run build
sudo php artisan storage:link

#権限まわり
sudo chmod -R 777 storage
sudo chmod -R 777 ./
