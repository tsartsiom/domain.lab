## Установка и настройка *vlmcsd* на *repo*

Вариант развертывания альтернативного KMS сервера, позволяющего активировать современные версии ОС Microsoft Windows/Windows Server и пакета Microsoft Office. Этот вариант реализован на базе ОС Debian GNU/Linux 11 (Bullseye) и исходных кодов открытого проекта [vlmcsd](https://github.com/Wind4/vlmcsd). Для своей работы KMS сервер vlmcsd не требует наличия купленных KMS-ключей или какой-либо онлайн-активации в Microsoft. 

Этот материал опирается на публично открытые программные продукты и не преследует цели нарушения норм действующего законодательства и правил лицензирования ПО.

Порядок сборки пакета *vlmcsd* под Debian приведет [тут](https://blog.it-kb.ru/2022/09/29/kms-activation-server-for-microsoft-windows-server-and-office-based-on-debian-linux-11-bullseye-and-vlmcsd-service-package/).

```bash
sudo dpkg -i vlmcsd_1113_amd64.deb
sudo mkdir /var/log/vlmcsd
sudo useradd -s /usr/sbin/nologin -r -M vlmcsd
sudo chown -R vlmcsd:vlmcsd /var/log/vlmcsd

# Указываем LogFile = /var/log/vlmcsd/vlmcsd.log
sudo nano /etc/vlmcsd/vlmcsd.ini

# Указываем vlmcsd в [Service] для User и Group
sudo systemctl edit vlmcsd.service
sudo systemctl daemon-reload
sudo systemctl restart vlmcsd.service

# проверяем порты и логи
sudo ss -tulnp | grep 1688
sudo tail /var/log/vlmcsd/vlmcsd.log
```