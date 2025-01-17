# Региональная маршрутизация для Wireguard

Набор скриптов для организации регионально-зависимой 
маршрутизации Wireguard (возможно применимо и к другим технологиям).

Для работы скриптов необходимо:

* GNU coreutils >= 8.30
* bash >= 5.0
* iproute2 >= 5.0.0
* jq >= 1.5
* curl >= 7.70.0

## regional-routing.sh

Скрипт скачивает IPv4 подсети РФ с RIPE, деаггрегирует в CIDR и прописывает 
в таблицу маршрутизации через default gateway.

Есть возможность отдельно прописывать подсети, маршрутизируемые локально, 
в файл `user_subnet_list.conf` в текущей директории (или иной файл через 
переменную окружения `$USER_LIST`) в формате CIDR.

Скрипт необходимо прописать в CRON от имени root с необходимой частотой и 
при перезагрузке, например:

```
0 0 * * * cd /etc/wireguard && /etc/wireguard/regional-routing.sh
@reboot cd /etc/wireguard && /etc/wireguard/regional-routing.sh
```

## post-up.sh и post-down.sh

Скрипты-хуки для Wireguard, настраивают интерфейс на прием пакетов и добавляют 
правило, чтобы не терялась связность при подключении выходного узла.

## Важно

Региональная маршрутизация работает, в случае подключения выходного узла к серверу.
Для этого необходимо настроить перенаправление всего трафика на этот узел в 
конфигурации (к примеру wg0.conf):

```ini
[Peer]
PublicKey = <omitted>
PresharedKey = <omitted>
AllowedIPs = 172.16.1.254, fd70:ffff:6600::254, 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```


