# Настройка zabbix

### Создание пользователя

Не рекомендуется подключаться по SSH под рутом. Для этого создаем пользователя *zabbix* при установке системы или после. Также устанавливаем пакет *sudo* и включаем в группу *sudo* пользователя *zabbix*.

```bash
apt install sudo
usermod -aG sudo zabbix
```
Перелогиваемся под пользователем *zabbix*.

### Настройка SSH

Отключаем IPv6 у демона *sshd* и запрещаем вход рута по ssh
```bash
sed -ri 's/^#?AddressFamily.*/AddressFamily inet/g' /etc/ssh/sshd_config
sed -ri 's/^#?ListenAddress 0.*/ListenAddress 0.0.0.0/g' /etc/ssh/sshd_config
sed -ri 's/^#?PermitRootLogin.*/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
```

Авторизация по публичному ключу пользователя *zabbix*

```bash
mkdir ~/.ssh && chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys

# добавляем наш публичный ключ
nano .ssh/authorized_keys
```

### Установка сетевых параметров, имени компьютера

Изменяем имя хоста, устанавливаем часовой пояс

```bash
sudo hostnamectl set-hostname zabbix.domain.lab
sudo timedatectl set-timezone Europe/Minsk
```

Настраиваем сетевой адрес  `sudo nano /etc/network/interfaces`

```bash
auto enp0s3
iface enp0s3 inet static
  address 192.168.69.18
  netmask 255.255.255.0
  gateway 192.168.0.254
dns-nameservers 192.168.69.1 192.168.69.2
```

Перезапускаем сетевую службу `sudo systemctl restart networking`

### Отключение IPv6

Из практических соображений IPv6 в настоящее время на сервере не нужен и его можно отключить.

```bash
sudo bash -c "cat >> /etc/sysctl.conf" << EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.ipv6.conf.tun0.disable_ipv6 = 1
EOF
```

Добавляем запрет на работу IPv6 в конфигурацию grub. Открываем конфиг */etc/default/grub* и добавляем к параметру GRUB_CMDLINE_LINUX еще одно значение **ipv6.disable=1**. Должно получиться примерно так:
```bash
GRUB_CMDLINE_LINUX_DEFAULT="ipv6.disable=1 quiet"
GRUB_CMDLINE_LINUX="ipv6.disable=1"
```

После этого обновляем конфиг загрузчика.

```bash
sudo update-grub
```

### Настройка хранения истории в *bash_history*

Первый параметр увеличивает размер файла до 10000 строк. Можно сделать и больше, хотя обычно хватает такого размера. Второй параметр указывает, что необходимо сохранять дату и время выполнения команды. Третья строка вынуждает сразу же после выполнения команды сохранять ее в историю. В последней строке мы создаем список исключений для тех команд, запись которых в историю не требуется.

```bash
cat >> ~/.bashrc << EOF
export HISTSIZE=10000
export HISTTIMEFORMAT="%h %d %H:%M:%S "
PROMPT_COMMAND="history -a"
export HISTIGNORE="ls:ll:history:w:htop"
EOF
```

### Отключение флуда сообщений в */var/log/messages*

Создаем файл конфигурации */etc/rsyslog.d/ignore-systemd-session-slice.conf*
```bash
sudo bash -c "cat > /etc/rsyslog.d/ignore-systemd-session-slice.conf" << EOF
if \$programname == "systemd" and (\$msg contains "Starting Session" or \$msg contains "Started Session" or \$msg contains "Created slice" or \$msg contains "Starting user-" or \$msg contains "Starting User Slice of" or \$msg contains "Removed session" or \$msg contains "Removed slice User Slice of" or \$msg contains "Stopping User Slice of") then stop
EOF
```

Перезапускаем службу

```bash
sudo systemctl restart rsyslog
```

### Настройка файрвола *nftables*

Добавляем в автозагрузку службу

```bash
sudo systemctl enable nftables.service
```

Создаем файл конфигурации */etc/nftables.conf*
```bash
sudo bash -c "cat > /etc/nftables.conf" << EOF
flush ruleset

table inet my_table {
  chain my_input {
    type filter hook input priority filter; policy drop;

    iif lo accept comment "Accept any localhost traffic"
    ct state invalid drop comment "Drop invalid connections"
    ct state established,related accept comment "Accept traffic originated from us"

    meta l4proto icmp icmp type { destination-unreachable, router-solicitation, router-advertisement, time-exceeded, parameter-problem } accept comment "Accept ICMP"

    tcp dport ssh accept comment "Accept SSH on port 22"

    tcp dport { http, https, 8008, 8080 } accept comment "Accept HTTP (ports 80, 443, 8008, 8080)"

    tcp dport { 10050, 10051 } accept comment "Accept Zabbix"
  }

  chain my_forward {
    type filter hook forward priority filter; policy drop;
    # Drop everything forwarded to us. We do not forward. That is routers job.
  }

  chain my_output {
    type filter hook output priority filter; policy accept;
    # Accept every outbound connection
  }
}
EOF
```

Перезапускаем службу

```bash
sudo systemctl restart nftables.service
```

## Настройка Zabbix

### Установка Zabbix server, frontend, agent

```bash
sudo apt install nginx mariadb-server php7.4-fpm
sudo apt install zabbix-server-mysql zabbix-frontend-php zabbix-nginx-conf zabbix-sql-scripts zabbix-agent
```

### Создание начальной базы данных

```bash
sudo mysql_secure_installation
mysql -uroot -p
```

```bash
create database zabbix character set utf8mb4 collate utf8mb4_bin;
create user zabbix@localhost identified by 'Password1234@!';
grant all privileges on zabbix.* to zabbix@localhost;
set global log_bin_trust_function_creators = 1;
quit;
```

### Импорт схемы и данных

```bash
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -p zabbix
```
После импорта схемы и данных отключаем *log_bin_trust_function_creators*

```bash
mysql -uroot -p
```

```bash
set global log_bin_trust_function_creators = 0;
quit;
```

### Настройка соединения с базой данных

Редактируем файл настроек */etc/zabbix/zabbix_server.conf*

```bash
DBPassword=Password1234@!
```

### Настройка фронтенда

Редактируем файл */etc/zabbix/nginx.conf* снимаем коменты и устанавливаем  *listen* и *server_name* директивы.


```bash
listen 80;
server_name zabbix.domain.lab;
```

Отключаем дефолтный сайт, перезагружаем службы

```bash
sudo rm -f /etc/nginx/sites-enabled/default
sudo systemctl restart zabbix-server zabbix-agent nginx php7.4-fpm
sudo systemctl enable zabbix-server zabbix-agent nginx php7.4-fpm
```