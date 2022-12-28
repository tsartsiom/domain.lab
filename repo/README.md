# Настройка repo

### Создание пользователя

Не рекомендуется подключаться по SSH под рутом. Для этого создаем пользователя *repoadmin* при установке системы или после. Также устанавливаем пакет *sudo* и включаем в группу *sudo* пользователя *repoadmin*.

```bash
apt install sudo
usermod -aG sudo repoadmin
```
Перелогиваемся под пользователем *repoadmin*.

### Настройка SSH

Отключаем IPv6 у демона *sshd* и запрещаем вход рута по ssh
```bash
sed -ri 's/^#?AddressFamily.*/AddressFamily inet/g' /etc/ssh/sshd_config
sed -ri 's/^#?ListenAddress 0.*/ListenAddress 0.0.0.0/g' /etc/ssh/sshd_config
sed -ri 's/^#?PermitRootLogin.*/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
```

Авторизация по публичному ключу пользователя *repoadmin*

```bash
mkdir ~/.ssh && chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys

# добавляем наш публичный ключ
nano .ssh/authorized_keys
```

### Установка сетевых параметров, имени компьютера

Изменяем имя хоста, устанавливаем часовой пояс

```bash
sudo hostnamectl set-hostname repo.domain.lab
sudo timedatectl set-timezone Europe/Minsk
```

Настраиваем сетевой адрес  `sudo nano /etc/network/interfaces`

```bash
auto enp0s3
iface enp0s3 inet static
  address 192.168.69.15
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

Добавляем запрет на работу IPv6 в конфигурацию grub. Открываем конфиг `sudo nano /etc/default/grub` и добавляем к параметру GRUB_CMDLINE_LINUX еще одно значение **ipv6.disable=1**. Должно получиться примерно так:
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

## Настройка локального репозитория в закрытой сети

### Настройка apt-mirror на машине с Интернетом

Устанавливаем пакет *apt-mirror*

`sudo apt install apt-mirror`

Включаем для синхронизации следующие репозитории:
- Стандартные Debian (`mirror.datacenter.by`)
- Zabbix (`repo.zabbix.com`)
- Proxmox (`download.proxmox.com`)
- Matrix Synapse (`packages.matrix.org`)

Для этого изменяем файл `sudo nano /etc/apt/mirror.list`, удаляя стандартные репозитории и добавляя наши. В `base_path` указываем место хранения скачанных репозиториев:

```bash
############# config ##################
#
set base_path    /media/share
#
# set mirror_path  $base_path/mirror
# set skel_path    $base_path/skel
# set var_path     $base_path/var
# set cleanscript $var_path/clean.sh
# set defaultarch  <running host architecture>
# set postmirror_script $var_path/postmirror.sh
# set run_postmirror 0
set nthreads     20
set _tilde 0
#
############# end config ##############

deb-amd64 http://mirror.datacenter.by/debian bullseye main contrib non-free
deb-amd64 http://mirror.datacenter.by/debian-security bullseye-security main contrib non-free
deb-amd64 http://mirror.datacenter.by/debian bullseye-updates main contrib non-free
deb-amd64 https://repo.zabbix.com/zabbix/6.2/debian bullseye main
deb-amd64 http://download.proxmox.com/debian/pve bullseye pve-no-subscription
deb-amd64 http://download.proxmox.com/debian/pbs bullseye pbs-no-subscription
deb-amd64 https://packages.matrix.org/debian bullseye main

clean http://mirror.datacenter.by/debian
clean http://mirror.datacenter.by/debian-security
clean https://repo.zabbix.com/zabbix/6.2/debian
clean http://download.proxmox.com/debian/pve
clean http://download.proxmox.com/debian/pbs
clean https://packages.matrix.org/debian
```

### Доступ на сервере *repo.domain.lab* по SMB3 к файловому серверу *fs1.domain.lab*

Файлы репозитория можно хранить как внутри виртуальной машины `repo`, так и в общей папке сервера `fs1`.

Для подключения к файловой шаре создаем файл с реквизитами доступа к файловому серверу:

```bash 
sudo bash -c "cat > /home/.smbcredentials" << EOF
username=Администратор
password=Password1234@!
domain=domain.lab
EOF
sudo chmod 400 /home/.smbcredentials
```

Установка пакета `cifs-utils`:
```bash
sudo apt install cifs-utils
sudo mkdir -p /media/share
sudo mount -t cifs -o rw,vers=3.0,credentials=/home/.smbcredentials //fs1.domain.lab/repo /media/share
```

Включение автоматического монтирования файловой при старте системы (обращаем внимание на то, чтобы в файле `/etc/network/interfaces` был параметр `auto enp0s3`)
```bash
sudo bash -c "cat >> /etc/fstab" << EOF
//fs1.domain.lab/repo /media/share cifs vers=3.0,credentials=/home/.smbcredentials,_netdev,noperm 0 0
EOF
```

### Настройка *nginx* на *repo.domain.lab*

Устанавливаем и настраиваем веб-сервер для репозитория

```bash
# Установка nginx и удаление конфига по-умолчанию
sudo apt install nginx
sudo systemctl enable nginx
sudo rm -f /etc/nginx/sites-enabled/default

# Создаем структуру папок в nginx
sudo mkdir -p /var/www/repo.domain.lab/html
sudo chown -R www-data:www-data /var/www/repo.domain.lab/html
sudo chmod -R 755 /var/www/repo.domain.lab

# Добавляем каталоги скачанных репозиториев
sudo ln -s /media/share/mirror/mirror.datacenter.by/debian /var/www/repo.domain.lab/html/debian
sudo ln -s /media/share/mirror/mirror.datacenter.by/debian-security /var/www/repo.domain.lab/html/debian-security
sudo ln -s /media/share/mirror/repo.zabbix.com/zabbix /var/www/repo.domain.lab/html/zabbix
sudo ln -s /media/share/mirror/download.proxmox.com /var/www/repo.domain.lab/html/proxmox
sudo ln -s /media/share/mirror/packages.matrix.org /var/www/repo.domain.lab/html/matrix
sudo ln -s /media/share/keys /var/www/repo.domain.lab/html/keys
sudo ln -s /media/share/centos /var/www/repo.domain.lab/html/centos

# Создаем файл конфигурации для nginx
sudo bash -c "cat > /etc/nginx/sites-available/repo.domain.lab" << EOF
server {
  listen 80;
  root /var/www/repo.domain.lab/html;
  index index.html;
  server_name repo.domain.lab;
  location / {
    try_files \$uri \$uri/ =404;
    autoindex on;
  }
}
EOF
sudo ln -s /etc/nginx/sites-available/repo.domain.lab /etc/nginx/sites-enabled/repo.domain.lab
sudo systemctl restart nginx
```

### Настройки клиентских машин

Настраиваем репозитории на клиентских машинах в папке */etc/apt*:
```bash
# Debian
sudo bash -c "cat > /etc/apt/sources.list.d/repo.domain.lab-debian.list" << EOF
deb http://repo.domain.lab/debian bullseye main contrib non-free
deb http://repo.domain.lab/debian-security bullseye-security main contrib non-free
deb http://repo.domain.lab/debian bullseye-updates main contrib non-free
EOF

# zabbix
echo "deb http://repo.domain.lab/zabbix/6.2/debian bullseye main" | sudo tee /etc/apt/sources.list.d/repo.domain.lab-zabbix.list

# proxmox
sudo bash -c "cat > /etc/apt/sources.list.d/repo.domain.lab-proxmox.list" << EOF
deb http://repo.domain.lab/proxmox/debian/pve bullseye pve-no-subscription
deb http://repo.domain.lab/proxmox/debian/pbs bullseye pbs-no-subscription
EOF

# matrix
echo "deb http://repo.domain.lab/matrix/debian bullseye main" | sudo tee /etc/apt/sources.list.d/repo.domain.lab-matrix.list

# gpg ключи
sudo wget http://repo.domain.lab/keys/zabbix-official-repo.gpg -O /etc/apt/trusted.gpg.d/zabbix-official-repo.gpg
sudo wget http://repo.domain.lab/keys/proxmox-release-bullseye.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bullseye.gpg
sudo wget http://repo.domain.lab/keys/matrix-org-archive-keyring.gpg -O /etc/apt/trusted.gpg.d/matrix-org-archive-keyring.gpg
```

### Использование локального репозитория на *repo*

При первоначальной установке в закрытой сети нету доступа к стандартным репозиториям, которые необходимы чтобы установить *nginx*, указываем путь к локальным репозиториям.

```bash
# Установка cifs-utils
sudo dpkg --install libtalloc2_2.3.1-2+b1_amd64.deb
sudo dpkg --install libtevent0_0.10.2-1_amd64.deb
sudo dpkg --install libwbclient0_4.13.13+dfsg-1~deb11u5_amd64.deb
sudo dpkg --install cifs-utils_6.11-3.1+deb11u1_amd64.deb
sudo dpkg --install keyutils_1.6.1-2_amd64.deb

# Создание локального репозитория после подлкючения к шаре
sudo bash -c "cat > /etc/apt/sources.list.d/local-repo.list" << EOF
deb file:/media/share/mirror/mirror.datacenter.by/debian bullseye main contrib non-free
deb file:/media/share/mirror/mirror.datacenter.by/debian-security bullseye-security main contrib non-free
deb file:/media/share/mirror/mirror.datacenter.by/debian bullseye-updates main contrib non-free
EOF
sudo apt update
```