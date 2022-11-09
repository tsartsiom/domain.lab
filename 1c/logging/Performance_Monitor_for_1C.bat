@ECHO OFF
ECHO Adding counter "1C_counter" ...
logman stop 1C_counter
logman delete 1C_counter
logman create counter 1C_counter -f bincirc -c "\Память\Обмен страниц/с" "\Память\Доступно МБ" "\Память\%% использования выделенной памяти" "\Физический диск(*)\Средняя длина очереди диска" "\Процессор(_Total)\%% загруженности процессора" "\Система\Длина очереди процессора" "\Логический диск(*)/%% свободного места" "\Физический диск(_Total)\Среднее время записи на диск (с)" "\Физический диск(_Total)\Среднее время чтения с диска (с)" "\Сетевой интерфейс(*)\Всего байт/с" -si 5 -v mmddhhmm -b 09:00:00 -max 100

logman start 1C_counter

c:\windows\system32\perfmon.exe

ECHO Complete