## Установка и настройка *vlmcsd*

Вариант развертывания альтернативного KMS сервера, позволяющего активировать современные версии ОС Microsoft Windows/Windows Server и пакета Microsoft Office. Этот вариант реализован на базе ОС Debian GNU/Linux 11 (Bullseye) и исходных кодов открытого проекта [vlmcsd](https://github.com/Wind4/vlmcsd). Для своей работы KMS сервер vlmcsd не требует наличия купленных KMS-ключей или какой-либо онлайн-активации в Microsoft. 

Этот материал опирается на публично открытые программные продукты и не преследует цели нарушения норм действующего законодательства и правил лицензирования ПО.

Порядок сборки пакета *vlmcsd* под [Debian 11](https://blog.it-kb.ru/2022/09/29/kms-activation-server-for-microsoft-windows-server-and-office-based-on-debian-linux-11-bullseye-and-vlmcsd-service-package/) и под [CentOS 8](https://winitpro.ru/index.php/2021/10/28/kms-server-vlmcsd-na-linux-dlya-aktivacii-windows-office/).

#### Порядок установки

```bash
# Устанавливаем пакет
dpkg -i vlmcsd_1113_amd64.deb

# Создаем папку для логов и пользователя для службы
mkdir /var/log/vlmcsd
useradd -s /usr/sbin/nologin -r -M vlmcsd
chown -R vlmcsd:vlmcsd /var/log/vlmcsd

# Указываем LogFile = /var/log/vlmcsd/vlmcsd.log
nano /etc/vlmcsd/vlmcsd.ini

# Указываем vlmcsd в [Service] для User и Group
systemctl edit vlmcsd.service
systemctl daemon-reload
systemctl restart vlmcsd.service

# проверяем порты и логи
ss -tulnp | grep 1688
tail /var/log/vlmcsd/vlmcsd.log
```