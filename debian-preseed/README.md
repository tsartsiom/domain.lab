# Автоматическая установка Debian

С файлом автоконфигурации [preseed.cfg](preseed.cfg) осуществляется автоматическая установка операционной системы Debian со следующими параметрами:
- таймзона `Europe/Minsk`
- имя хоста `debian11`, домен `domain.lab`
- сетевая конфигурация принимается от DHCP сервера, в случае его отсутствия - вводятся вручную
- в качестве репозитория указывается http://mirror.datacenter.by
- пароль для пользователя *root* `Password1234@!`
- форматируется весь жесткий диск MBR для BIOS, GPT для UEFI
- устанавливается пакет `openssh-server`
- производятся базовые настройки SSH, импорт SSH ключей, настройка .bashrc для пользователя *root*

Ниже указан порядок модификации установочного образа, согласно файлу автоконфигурации `preseed.cfg`.

### Установка xorriso

```bash
apt -y install xorriso
```

### Распаковка файло из ISO-образа в `isofiles`

```bash
xorriso -osirrox on -indev debian-11.5.0-amd64-netinst.iso -extract / isofiles/
dd if=debian-11.5.0-amd64-netinst.iso bs=1 count=432 of=isohdpfx.bin
```

### Добавление файла конфигурации `preseed.cfg` в initrd

```bash
chmod +w -R isofiles/install.amd/
gunzip isofiles/install.amd/initrd.gz
echo preseed.cfg | cpio -H newc -o -A -F isofiles/install.amd/initrd
gzip isofiles/install.amd/initrd
chmod -w -R isofiles/install.amd/
```

### Изменение загрузчика

В файле `nano isofiles/isolinux/isolinux.cfg` коментируем строку `#default vesamenu.c32`.

Добавляем строки в файл `nano isofiles/boot/grub/grub.cfg`:

```
set timeout_style=hidden
set timeout=0
set default=1
```

### Пересчет хеш-сумм

```bash
cd isofiles/
chmod a+w md5sum.txt
md5sum `find -follow -type f` > md5sum.txt
chmod a-w md5sum.txt
```

### Создание ISO-образа c автоматической установкой

```bash
cd ..
xorriso -as mkisofs \
   -r -V 'Debian 11.5.0 amd64 n preseed' \
   -o debian-11.5.0-amd64-unattended.iso \
   -J -joliet-long -cache-inodes \
   -isohybrid-mbr isohdpfx.bin \
   -b isolinux/isolinux.bin \
   -c isolinux/boot.cat \
   -boot-load-size 4 -boot-info-table -no-emul-boot \
   -eltorito-alt-boot \
   -e boot/grub/efi.img \
   -no-emul-boot -isohybrid-gpt-basdat -isohybrid-apm-hfsplus \
   isofiles
```